//! The engine for the Mac app, bound to Swift with UniFFI. Commands, snapshots and
//! the other structured values cross as JSON, display lists as words, files as bytes.

use crate::color::{self, ColorMode};
use crate::doc::{self, Command, Doc};
use crate::{Lists, display_list::encode, image, inks, text, variable};
use serde::Serialize;
use std::cell::{Cell, RefCell};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread::{self, ThreadId};

#[derive(Debug, uniffi::Error)]
pub enum EngineError {
    Failed { message: String },
}

impl std::fmt::Display for EngineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let EngineError::Failed { message } = self;
        f.write_str(message)
    }
}

impl std::error::Error for EngineError {}

impl From<String> for EngineError {
    fn from(message: String) -> Self {
        EngineError::Failed { message }
    }
}

fn json_err(e: serde_json::Error) -> EngineError {
    e.to_string().into()
}

/// Display lists cross as their words in little endian, which Swift reads in place.
fn words(list: &[u32]) -> Vec<u8> {
    list.iter().flat_map(|w| w.to_le_bytes()).collect()
}

fn json(v: &impl Serialize) -> Result<String, EngineError> {
    serde_json::to_string(v).map_err(json_err)
}

/// Fonts, images and the CMYK profile live in thread locals, so a document stays on
/// the thread that made it; Swift keeps it on the main actor, and an export makes
/// its own on its own thread.
struct Confined<T> {
    owner: ThreadId,
    value: RefCell<T>,
}

// SAFETY: every access goes through `with`, which panics off the owning thread.
unsafe impl<T> Send for Confined<T> {}
unsafe impl<T> Sync for Confined<T> {}

impl<T> Confined<T> {
    fn new(value: T) -> Self {
        Confined {
            owner: thread::current().id(),
            value: RefCell::new(value),
        }
    }

    fn with<R>(&self, f: impl FnOnce(&mut T) -> R) -> R {
        assert_eq!(
            thread::current().id(),
            self.owner,
            "a Satz document is used off the thread that made it"
        );
        f(&mut self.value.borrow_mut())
    }
}

struct State {
    doc: Doc,
    lists: Lists,
}

static IDS: AtomicU64 = AtomicU64::new(1);

thread_local! {
    /// The document whose profile the thread's colour management holds.
    static ACTIVE: Cell<u64> = const { Cell::new(0) };
}

/// A Satz document and the display lists drawn from it.
#[derive(uniffi::Object)]
pub struct Core {
    id: u64,
    state: Confined<State>,
}

impl Core {
    fn make(doc: Doc) -> Arc<Core> {
        let id = IDS.fetch_add(1, Ordering::Relaxed);
        ACTIVE.set(id);
        Arc::new(Core {
            id,
            state: Confined::new(State {
                doc,
                lists: Lists::default(),
            }),
        })
    }

    fn with<R>(&self, f: impl FnOnce(&mut State) -> R) -> R {
        self.state.with(|s| {
            if ACTIVE.get() != self.id {
                s.doc.use_profile();
                ACTIVE.set(self.id);
            }
            f(s)
        })
    }
}

#[uniffi::export]
impl Core {
    #[uniffi::constructor]
    pub fn new() -> Arc<Core> {
        Core::make(Doc::default())
    }

    /// The document Satz shows on its first start.
    #[uniffi::constructor]
    pub fn sample() -> Arc<Core> {
        Core::make(Doc::sample())
    }

    /// An empty document of `pages` pages `w` × `h` pt.
    #[uniffi::constructor]
    pub fn blank(w: f64, h: f64, pages: u32, facing: bool) -> Arc<Core> {
        Core::make(Doc::blank(w, h, pages as usize, facing, ColorMode::Cmyk))
    }

    /// The document saved as `bytes`.
    #[uniffi::constructor]
    pub fn load(bytes: Vec<u8>) -> Result<Arc<Core>, EngineError> {
        Ok(Core::make(Doc::load(&bytes)?))
    }

    /// Applies the JSON `command` and returns the ids it made.
    pub fn apply(&self, command: String) -> Result<Vec<String>, EngineError> {
        let cmd: Command = serde_json::from_str(&command).map_err(json_err)?;
        self.with(|s| Ok(s.doc.apply(cmd)?))
    }

    /// What the last command changed beyond what it was asked to.
    pub fn notes(&self) -> Vec<String> {
        self.with(|s| s.doc.notes())
    }

    pub fn snapshot(&self) -> Result<String, EngineError> {
        self.with(|s| json(&*s.doc.snapshot()))
    }

    /// Changes whenever the document does.
    pub fn version(&self) -> String {
        self.with(|s| s.doc.version())
    }

    pub fn save(&self) -> Vec<u8> {
        self.with(|s| s.doc.save())
    }

    /// Path from the topmost page child down to the deepest node at (x, y) in pt.
    pub fn hit(&self, page: String, x: f64, y: f64, tolerance: f64) -> Vec<String> {
        self.with(|s| s.doc.hit(&page, x, y, tolerance))
    }

    /// The layer of the page's master at (x, y) in pt that the page shows.
    pub fn master_hit(&self, page: String, x: f64, y: f64, tolerance: f64) -> Option<String> {
        self.with(|s| s.doc.master_hit(&page, x, y, tolerance))
    }

    pub fn display_list(&self, page: String) -> Vec<u8> {
        self.with(|s| words(&s.lists.drawn(&s.doc, &page).1))
    }

    /// The version of the display list of the page `page`, which changes only with it.
    pub fn list_version(&self, page: String) -> u32 {
        self.with(|s| s.lists.drawn(&s.doc, &page).0)
    }

    /// The display list of the page as its inverted C, M and Y plate, or its K plate.
    pub fn plate(&self, page: String, k: bool) -> Vec<u8> {
        self.with(|s| words(&encode(&s.doc.plate(&page, k))))
    }

    /// [x, top, bottom] in pt of a caret before the UTF-16 `index` of the text `id`.
    pub fn caret(&self, id: String, index: u32) -> Result<Vec<f64>, EngineError> {
        self.with(|s| Ok(s.doc.caret(&id, index as usize)?.to_vec()))
    }

    /// The transform [a b c d e f] that turns the layer `id` on its page.
    pub fn turn(&self, id: String) -> Result<Vec<f32>, EngineError> {
        self.with(|s| Ok(s.doc.turn_of(&id)?.to_vec()))
    }

    /// Whether the text frame `to` can join the thread after `from`.
    pub fn can_thread(&self, from: String, to: String) -> bool {
        self.with(|s| s.doc.threadable(&from, &to).is_ok())
    }

    /// The frame of the thread of the text `id` that holds the UTF-16 `index`.
    pub fn text_frame(&self, id: String, index: u32) -> Result<String, EngineError> {
        self.with(|s| Ok(s.doc.text_frame(&id, index as usize)?))
    }

    /// The UTF-16 index of the character boundary of the text `id` nearest (x, y) in pt.
    pub fn text_index(&self, id: String, x: f64, y: f64) -> Result<u32, EngineError> {
        self.with(|s| Ok(s.doc.text_index(&id, x, y)? as u32))
    }

    /// UTF-16 start and end of the line of the text `id` that holds `index`.
    pub fn text_line(&self, id: String, index: u32) -> Result<Vec<u32>, EngineError> {
        self.with(|s| {
            let l = s.doc.text_line(&id, index as usize)?;
            Ok(l.map(|i| i as u32).to_vec())
        })
    }

    /// Display list of the selection from `anchor` to `focus` in the text `id` on the
    /// page `page`, or of a caret `caret_width` pt wide.
    pub fn text_overlay(
        &self,
        id: String,
        anchor: u32,
        focus: u32,
        caret_width: f32,
        page: String,
    ) -> Result<Vec<u8>, EngineError> {
        self.with(|s| {
            let ops =
                s.doc
                    .text_overlay(&id, anchor as usize, focus as usize, caret_width, &page)?;
            Ok(words(&encode(&ops)))
        })
    }

    /// The inks of the page `page` as it prints at `ppi`.
    pub fn inks(&self, page: String, ppi: f32) -> Option<Arc<Inks>> {
        self.with(|s| s.doc.inks(&page, ppi))
            .map(|i| Arc::new(Inks(i)))
    }

    /// A hash of the page `page` as it prints; its inks change only with it.
    pub fn printed(&self, page: String) -> Option<u64> {
        self.with(|s| s.doc.printed(&page))
    }

    /// The page `page` as a PNG at `ppi`.
    pub fn png(&self, page: String, ppi: f32) -> Option<Vec<u8>> {
        self.with(|s| s.doc.png(&page, ppi))
    }

    /// The pages at `indices` as a PDF titled `title`, made at `date` in ISO 8601 UTC.
    pub fn pdf(&self, title: String, date: String, indices: Vec<u32>) -> Vec<u8> {
        self.with(|s| s.doc.pdf(&title, &date, &indices))
    }

    /// A ZIP for the printer: the document, the PDF of the pages, its fonts and images.
    pub fn package(&self, title: String, date: String, indices: Vec<u32>) -> Vec<u8> {
        self.with(|s| s.doc.package(&title, &date, &indices))
    }

    /// Makes `icc` the CMYK profile of the document, or FOGRA51 for none.
    pub fn set_profile(&self, icc: Option<Vec<u8>>) -> Result<(), EngineError> {
        self.with(|s| Ok(s.doc.set_profile(icc)?))
    }

    /// Adds a TrueType, OpenType, WOFF or WOFF2 font; its typeface as JSON.
    pub fn add_font(&self, bytes: Vec<u8>) -> Result<String, EngineError> {
        self.with(|s| json(&s.doc.add_font(&bytes)?))
    }

    /// Removes the added font `hash`.
    pub fn remove_font(&self, hash: String) -> Result<(), EngineError> {
        self.with(|s| Ok(s.doc.remove_font(&hash)?))
    }

    /// Adds a PNG or JPEG file to the document's images; its hash and size as JSON,
    /// for the command `placeImage`.
    pub fn add_image(&self, bytes: Vec<u8>) -> Result<String, EngineError> {
        self.with(|s| json(&s.doc.add_image(&bytes)?))
    }
}

/// The plates of a page, see `inks::Inks`.
#[derive(uniffi::Object)]
pub struct Inks(inks::Inks);

#[uniffi::export]
impl Inks {
    pub fn width(&self) -> u32 {
        self.0.width()
    }

    pub fn height(&self) -> u32 {
        self.0.height()
    }

    /// The names of the spot colors, in the order of their plates after K.
    pub fn spots(&self) -> Vec<String> {
        self.0.spots()
    }

    /// The highest coverage of each plate in percent.
    pub fn max(&self) -> Vec<f32> {
        self.0.max()
    }

    /// The total coverage of each pixel in percent, row by row.
    pub fn coverage(&self) -> Vec<f32> {
        self.0.coverage()
    }

    /// RGBA pixels of the plate `on`, see `inks::Inks::image`.
    pub fn image(&self, on: u32, limit: f32, over: bool, gamut: bool) -> Vec<u8> {
        self.0.image(on, limit, over, gamut)
    }
}

/// The file of the image `id` of display lists.
#[uniffi::export]
pub fn image_bytes(id: u32) -> Vec<u8> {
    image::bytes(id).to_vec()
}

/// The image to decode for the image `id` of display lists and [k, m, o] that adjust
/// it, or nothing when it draws as it is.
#[uniffi::export]
pub fn image_source(id: u32) -> Vec<f64> {
    image::source(id).map_or(Vec::new(), |(source, f)| {
        [source as f64]
            .into_iter()
            .chain(f.map(f64::from))
            .collect()
    })
}

/// The file of the font `id` of display lists.
#[uniffi::export]
pub fn font_bytes(id: u32) -> Vec<u8> {
    text::font_bytes(id).to_vec()
}

/// The number of font ids, removed ones included.
#[uniffi::export]
pub fn fonts_added() -> u32 {
    text::fonts_added() as u32
}

/// The id of the font `hash`, the bundled one for none, and its characters as
/// [code point, Unicode name], as JSON.
#[uniffi::export]
pub fn characters(hash: Option<String>) -> Result<String, EngineError> {
    json(&text::characters(hash.as_deref()))
}

/// The name and hash of the font `bytes` as JSON.
#[uniffi::export]
pub fn typeface(bytes: Vec<u8>) -> Result<String, EngineError> {
    json(&text::typeface(&bytes)?)
}

/// The letters that the page numbers of the master `name` show.
#[uniffi::export]
pub fn prefix(name: String) -> String {
    doc::prefix(&name)
}

/// Screen preview of a CMYK color as 0xRRGGBB.
#[uniffi::export]
pub fn preview(c: f32, m: f32, y: f32, k: f32) -> u32 {
    let [r, g, b] = color::to_rgb([c, m, y, k]).map(|v| (v * 255.0).round() as u32);
    r << 16 | g << 8 | b
}

/// CMYK of the 0xRRGGBB color `rgb` in the print condition.
#[uniffi::export]
pub fn to_cmyk(rgb: u32) -> Vec<f32> {
    color::separate(rgb).to_vec()
}

/// `"black"`, `"white"` or `"gray"` in the JSON color mode `mode`, as JSON.
#[uniffi::export]
pub fn neutral(name: String, mode: String) -> Result<String, EngineError> {
    let mode = serde_json::from_str(&mode).map_err(json_err)?;
    json(&match name.as_str() {
        "black" => color::Color::black(mode),
        "white" => color::Color::white(mode),
        _ => color::Color::gray(mode),
    })
}

/// The JSON `color` with swatches and variables replaced by what they stand for in
/// `scope`, a palette with `modes`, as JSON.
#[uniffi::export]
pub fn resolve(color: String, scope: String) -> Result<String, EngineError> {
    #[derive(serde::Deserialize)]
    struct Owned {
        #[serde(flatten)]
        palette: variable::Palette,
        #[serde(default)]
        modes: variable::Modes,
    }
    let color: color::Color = serde_json::from_str(&color).map_err(json_err)?;
    let s: Owned = serde_json::from_str(&scope).map_err(json_err)?;
    let scope = variable::Scope {
        palette: &s.palette,
        modes: &s.modes,
    };
    json(&color.resolve(&scope))
}

/// CMYK of RGB on a grid of 33 steps per channel as RGBA pixels, see `crate::separation`.
#[uniffi::export]
pub fn separation() -> Vec<u8> {
    crate::separation()
}

/// Screen colors of CMYK on a grid of 17 steps per ink as RGBA pixels, see `crate::lut`.
#[uniffi::export]
pub fn lut() -> Vec<u8> {
    crate::lut()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_core_applies_json_commands_and_saves() {
        let core = Core::sample();
        let snap: serde_json::Value = serde_json::from_str(&core.snapshot().unwrap()).unwrap();
        let page = snap["pages"][0]["id"].as_str().unwrap().to_string();
        let v = core.list_version(page.clone());
        let cmd = format!(r#"{{"type":"duplicatePage","id":"{page}"}}"#);
        let made = core.apply(cmd).unwrap();
        assert_eq!(made.len(), 1);
        assert_eq!(core.list_version(page.clone()), v);
        assert_eq!(core.display_list(made[0].clone()).len() % 4, 0);
        assert!(!core.display_list(made[0].clone()).is_empty());
        let again = Core::load(core.save()).unwrap();
        let snap: serde_json::Value = serde_json::from_str(&again.snapshot().unwrap()).unwrap();
        assert_eq!(snap["pages"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn a_bad_command_is_an_error() {
        let core = Core::sample();
        assert!(core.apply("{\"type\":\"nope\"}".into()).is_err());
        assert!(
            core.apply("{\"type\":\"deletePage\",\"id\":\"x\"}".into())
                .is_err()
        );
    }
}
