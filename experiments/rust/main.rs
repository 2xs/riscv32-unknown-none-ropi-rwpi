#![no_std]
#![no_main]

use core::arch::asm;
use core::panic::PanicInfo;

const SEMI_SYS_WRITE0: isize = 0x04;
const SEMI_SYS_EXIT: isize = 0x18;
const SEMI_SYS_EXIT_EXTENDED: isize = 0x20;
const ADP_STOPPED_APPLICATION_EXIT: i32 = 0x20026;

#[unsafe(no_mangle)]
pub static mut G: i32 = 41;

#[unsafe(no_mangle)]
pub static mut Z: i32 = 0;

#[unsafe(no_mangle)]
pub static OK: [u8; 28] = *b"Rust pure semihost RWPI OK\n\0";

#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    loop {}
}

unsafe fn semihost_call(op: isize, arg: *const ()) -> isize {
    let mut a0 = op;
    let a1 = arg;
    unsafe {
        asm!(
            ".option push",
            ".option norvc",
            "slli zero, zero, 0x1f",
            "ebreak",
            "srai zero, zero, 7",
            ".option pop",
            inlateout("a0") a0,
            in("a1") a1,
            options(nostack)
        );
    }
    a0
}

unsafe fn semihost_write0(s: *const u8) {
    unsafe { semihost_call(SEMI_SYS_WRITE0, s.cast()); }
}

unsafe fn semihost_exit(code: i32) -> ! {
    let block = [ADP_STOPPED_APPLICATION_EXIT, code];
    unsafe {
        semihost_call(SEMI_SYS_EXIT_EXTENDED, block.as_ptr().cast());
        semihost_call(SEMI_SYS_EXIT, (code as usize) as *const ());
    }
    loop {}
}

unsafe fn load_i32(p: *const i32) -> i32 {
    let out: i32;
    unsafe {
        asm!(
            "lw {out}, 0({ptr})",
            out = out(reg) out,
            ptr = in(reg) p,
            options(nostack, readonly)
        );
    }
    out
}

unsafe fn store_i32(p: *mut i32, value: i32) {
    unsafe {
        asm!(
            "sw {value}, 0({ptr})",
            ptr = in(reg) p,
            value = in(reg) value,
            options(nostack)
        );
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_sum() -> i32 {
    unsafe { load_i32((&raw const G).cast()) + load_i32((&raw const Z).cast()) }
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_g_addr() -> *mut i32 {
    (&raw mut G).cast()
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_inc() {
    unsafe {
        let g = load_i32((&raw const G).cast()) + 1;
        store_i32((&raw mut G).cast(), g);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn main() -> i32 {
    unsafe {
        semihost_write0((&raw const OK).cast());
        semihost_exit(0);
    }
}
