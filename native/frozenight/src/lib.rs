use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

use cozy_chess::{Board, File, Move, Piece, Square};
use frozenight::{Eval, MtFrozenight, SearchInfo, TimeConstraint};

struct EngineState {
    engine: MtFrozenight,
    result: Option<SearchResult>,
}

/// ABI 2 owns one engine per handle. The old global entry points remain below
/// solely so an already-released dev2 executable can load a repaired DLL.
pub struct FrozenightHandle(Mutex<EngineState>);

struct SearchResult {
    nodes: u64,
    best_move: CString,
    score_cp: i32,
    depth: i32,
}

fn eval_to_cp(eval: Eval) -> i32 {
    bytemuck::cast::<Eval, i16>(eval) as i32
}

#[no_mangle]
pub extern "C" fn frozenight_abi_version() -> u32 { 2 }

#[no_mangle]
pub extern "C" fn frozenight_create(hash_mb: u32) -> *mut FrozenightHandle {
    Box::into_raw(Box::new(FrozenightHandle(Mutex::new(EngineState {
        engine: MtFrozenight::new(hash_mb as usize), result: None,
    }))))
}

unsafe fn state<'a>(handle: *mut FrozenightHandle) -> Option<std::sync::MutexGuard<'a, EngineState>> {
    handle.as_ref().map(|h| h.0.lock().unwrap_or_else(|e| e.into_inner()))
}

#[no_mangle]
pub unsafe extern "C" fn frozenight_set_position_v2(
    handle: *mut FrozenightHandle, fen: *const c_char, moves: *const c_char,
) -> i32 {
    let mut guard = match state(handle) { Some(s) => s, None => return -2 };
    let fen_str = if fen.is_null() { return -1; } else {
        match CStr::from_ptr(fen).to_str() { Ok(s) => s, Err(_) => return -1 }
    };
    let board = if fen_str == "startpos" { Board::default() } else {
        match fen_str.parse::<Board>() { Ok(b) => b, Err(_) => return -1 }
    };
    let mut current = board.clone();
    let mut move_list = Vec::new();
    if !moves.is_null() {
        let text = match CStr::from_ptr(moves).to_str() { Ok(s) => s, Err(_) => return -1 };
        for uci in text.split_whitespace() {
            let mv = match parse_uci_move(&current, uci) { Some(m) => m, None => return -3 };
            current.play(mv);
            move_list.push(mv);
        }
    }
    guard.engine.set_position(board, move_list.into_iter());
    guard.result = None;
    0
}

#[no_mangle]
pub unsafe extern "C" fn frozenight_search_bounded_v2(
    handle: *mut FrozenightHandle, depth: i32, max_nodes: u64,
) -> i32 {
    let mut guard = match state(handle) { Some(s) => s, None => return -1 };
    if !(1..=64).contains(&depth) { return -4; }
    let board = guard.engine.board().clone();
    let done = Arc::new((Mutex::new(false), Condvar::new()));
    let info_done = done.clone();
    let finish_done = done.clone();
    let holder = Arc::new(Mutex::new(None));
    let info_result = holder.clone();
    let finish_result = holder.clone();
    let info_board = board.clone();
    let finish_board = board.clone();
    let info_result = move |info: &SearchInfo| {
        let r = SearchResult {
            nodes: info.nodes,
            best_move: CString::new(move_to_uci(&info_board, info.best_move)).unwrap_or_default(),
            score_cp: eval_to_cp(info.eval), depth: info.depth as i32,
        };
        *info_result.lock().unwrap() = Some(r);
    };
    let finish_result = move |info: &SearchInfo| {
        let r = SearchResult {
            nodes: info.nodes,
            best_move: CString::new(move_to_uci(&finish_board, info.best_move)).unwrap_or_default(),
            score_cp: eval_to_cp(info.eval), depth: info.depth as i32,
        };
        *finish_result.lock().unwrap() = Some(r);
        *info_done.0.lock().unwrap() = true;
        info_done.1.notify_all();
    };
    guard.engine.search(TimeConstraint {
        depth: depth as i16, nodes: if max_nodes == 0 { u64::MAX } else { max_nodes },
        ..TimeConstraint::INFINITE
    }, info_result, finish_result);
    let mut finished = finish_done.0.lock().unwrap();
    while !*finished { finished = finish_done.1.wait(finished).unwrap(); }
    guard.result = holder.lock().unwrap().take();
    if guard.result.is_some() { 0 } else { -5 }
}

#[no_mangle]
pub unsafe extern "C" fn frozenight_get_best_move_v2(handle: *mut FrozenightHandle) -> *const c_char {
    state(handle).and_then(|s| s.result.as_ref().map(|r| r.best_move.as_ptr())).unwrap_or(std::ptr::null())
}
#[no_mangle]
pub unsafe extern "C" fn frozenight_get_nodes_v2(handle: *mut FrozenightHandle) -> i64 {
    state(handle).and_then(|s| s.result.as_ref().map(|r| r.nodes.min(i64::MAX as u64) as i64)).unwrap_or(0)
}
#[no_mangle]
pub unsafe extern "C" fn frozenight_get_score_v2(handle: *mut FrozenightHandle) -> i32 {
    state(handle).and_then(|s| s.result.as_ref().map(|r| r.score_cp)).unwrap_or(0)
}
#[no_mangle]
pub unsafe extern "C" fn frozenight_get_depth_v2(handle: *mut FrozenightHandle) -> i32 {
    state(handle).and_then(|s| s.result.as_ref().map(|r| r.depth)).unwrap_or(0)
}
/// # Safety
/// Call exactly once, after all searches using this handle have returned.
#[no_mangle]
pub unsafe extern "C" fn frozenight_destroy(handle: *mut FrozenightHandle) {
    if !handle.is_null() { drop(Box::from_raw(handle)); }
}

struct LegacyHandle(*mut FrozenightHandle);
unsafe impl Send for LegacyHandle {}
static LEGACY: Mutex<LegacyHandle> = Mutex::new(LegacyHandle(std::ptr::null_mut()));
#[no_mangle]
pub extern "C" fn frozenight_init(hash_mb: u32) -> i32 {
    let mut legacy = LEGACY.lock().unwrap();
    if !legacy.0.is_null() { unsafe { frozenight_destroy(legacy.0); } }
    legacy.0 = frozenight_create(hash_mb);
    if legacy.0.is_null() { -1 } else { 0 }
}
#[no_mangle]
pub unsafe extern "C" fn frozenight_set_position(fen: *const c_char, moves: *const c_char) -> i32 {
    frozenight_set_position_v2(LEGACY.lock().unwrap().0, fen, moves)
}
#[no_mangle]
pub unsafe extern "C" fn frozenight_search(depth: i32) -> i32 { frozenight_search_bounded(depth, 0) }
#[no_mangle]
pub unsafe extern "C" fn frozenight_search_bounded(depth: i32, nodes: u64) -> i32 {
    frozenight_search_bounded_v2(LEGACY.lock().unwrap().0, depth, nodes)
}
#[no_mangle]
pub unsafe extern "C" fn frozenight_get_best_move() -> *const c_char { frozenight_get_best_move_v2(LEGACY.lock().unwrap().0) }
#[no_mangle]
pub unsafe extern "C" fn frozenight_get_nodes() -> i64 { frozenight_get_nodes_v2(LEGACY.lock().unwrap().0) }
#[no_mangle]
pub unsafe extern "C" fn frozenight_get_score() -> i32 { frozenight_get_score_v2(LEGACY.lock().unwrap().0) }
#[no_mangle]
pub unsafe extern "C" fn frozenight_get_depth() -> i32 { frozenight_get_depth_v2(LEGACY.lock().unwrap().0) }
#[no_mangle]
pub extern "C" fn frozenight_dispose() {
    let mut legacy = LEGACY.lock().unwrap();
    unsafe { frozenight_destroy(legacy.0); }
    legacy.0 = std::ptr::null_mut();
}


/// Standard-UCI text for a move cozy-chess produced.
///
/// cozy-chess encodes castling as king-takes-own-rook (e1h1 / e1a1), which is
/// the Chess960 convention. The app speaks ordinary UCI, where castling is the
/// king moving two files (e1g1 / e1c1) — so the raw square pair was rejected as
/// an illegal move the first time the engine wanted to castle, which ended the
/// game.
fn move_to_uci(board: &Board, mv: Move) -> String {
    let mut to = mv.to;
    let is_castle = board.piece_on(mv.from) == Some(Piece::King)
        && board.color_on(mv.to) == Some(board.side_to_move());
    if is_castle {
        let file = if mv.to.file() > mv.from.file() {
            File::G
        } else {
            File::C
        };
        to = Square::new(file, mv.from.rank());
    }
    let promo = match mv.promotion {
        Some(p) => format!("{}", p).to_lowercase(),
        None => String::new(),
    };
    format!("{}{}{}", mv.from, to, promo)
}


fn parse_uci_move(board: &Board, uci: &str) -> Option<Move> {
    if uci.len() < 4 { return None; }
    let from: Square = uci[0..2].parse().ok()?;
    let mut to: Square = uci[2..4].parse().ok()?;
    let promotion = if uci.len() > 4 {
        match uci.as_bytes()[4] {
            b'q' => Some(cozy_chess::Piece::Queen),
            b'r' => Some(cozy_chess::Piece::Rook),
            b'b' => Some(cozy_chess::Piece::Bishop),
            b'n' => Some(cozy_chess::Piece::Knight),
            _ => None,
        }
    } else {
        None
    };

    // Ordinary UCI castling (king two files) has to be translated to
    // cozy-chess's king-takes-rook form before it can be matched.
    if board.piece_on(from) == Some(Piece::King)
        && (to.file() as i8 - from.file() as i8).abs() == 2
    {
        let rooks = board.colors(board.side_to_move()) & board.pieces(Piece::Rook)
            & from.rank().bitboard();
        let kingside = to.file() > from.file();
        for rook in rooks {
            if (rook.file() > from.file()) == kingside {
                to = rook;
                break;
            }
        }
    }

    let mut result = None;
    board.generate_moves(|moves| {
        for mv in moves {
            if mv.from == from && mv.to == to {
                match (promotion, mv.promotion) {
                    (Some(p), Some(mp)) if p == mp => { result = Some(mv); }
                    (None, None) => { result = Some(mv); }
                    (None, Some(_)) => { result = Some(mv); }
                    _ => {}
                }
            }
        }
        // cozy-chess: returning `true` *stops* generation, `false` continues.
        result.is_some()
    });
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn independent_handles_do_not_share_position_or_results() {
        unsafe {
            let a = frozenight_create(1);
            let b = frozenight_create(1);
            assert!(!a.is_null() && !b.is_null() && a != b);
            let start = CString::new("startpos").unwrap();
            let black = CString::new("e2e4").unwrap();
            let invalid = CString::new("e2e4 e2e4").unwrap();
            let empty = CString::new("").unwrap();
            assert_eq!(frozenight_set_position_v2(a, start.as_ptr(), empty.as_ptr()), 0);
            assert_eq!(frozenight_set_position_v2(b, start.as_ptr(), black.as_ptr()), 0);
            let workers: Vec<_> = [(a as usize, 1100), (b as usize, 2300)].into_iter().map(|(address, nodes)| {
                std::thread::spawn(move || {
                    let h = address as *mut FrozenightHandle;
                    assert_eq!(frozenight_search_bounded_v2(h, 3, nodes), 0);
                    let mv = CStr::from_ptr(frozenight_get_best_move_v2(h)).to_str().unwrap().to_owned();
                    (mv, frozenight_get_nodes_v2(h))
                })
            }).collect();
            let results: Vec<_> = workers.into_iter().map(|w| w.join().unwrap()).collect();
            eprintln!("native concurrency results: {results:?}");
            assert!(results.iter().all(|(m, n)| m.len() >= 4 && *n > 0));
            assert_eq!(frozenight_set_position_v2(a, start.as_ptr(), invalid.as_ptr()), -3);
            assert_eq!(frozenight_set_position_v2(b, start.as_ptr(), empty.as_ptr()), 0);
            frozenight_destroy(a);
            frozenight_destroy(b);
        }
    }

    #[test]
    fn invalid_handles_and_arguments_fail_without_success() {
        unsafe {
            assert_eq!(frozenight_search_bounded_v2(std::ptr::null_mut(), 2, 100), -1);
            assert_eq!(frozenight_get_nodes_v2(std::ptr::null_mut()), 0);
            assert!(frozenight_get_best_move_v2(std::ptr::null_mut()).is_null());
            let h = frozenight_create(1);
            assert_eq!(frozenight_search_bounded_v2(h, 0, 100), -4);
            assert_eq!(frozenight_search_bounded_v2(h, 65, 100), -4);
            frozenight_destroy(h);
        }
    }
}
