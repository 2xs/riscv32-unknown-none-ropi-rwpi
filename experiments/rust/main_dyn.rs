#![no_std]
#![no_main]

use core::arch::asm;
use core::hint::black_box;
use core::panic::PanicInfo;

const SEMI_SYS_WRITE0: isize = 0x04;
const SEMI_SYS_EXIT: isize = 0x18;
const SEMI_SYS_EXIT_EXTENDED: isize = 0x20;
const ADP_STOPPED_APPLICATION_EXIT: i32 = 0x20026;

trait Value {
    fn value(&self) -> i32;
}

struct Thing(i32);

impl Value for Thing {
    fn value(&self) -> i32 {
        self.0
    }
}

#[unsafe(no_mangle)]
pub static THING: Thing = Thing(42);

#[unsafe(no_mangle)]
pub static OK: [u8; 19] = *b"Rust dyn trait OK\n\0";

#[unsafe(no_mangle)]
pub static FAIL: [u8; 23] = *b"Rust dyn trait failed\n\0";

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

#[unsafe(no_mangle)]
pub extern "C" fn dyn_value() -> i32 {
    let v: &dyn Value = black_box(&THING as &dyn Value);
    v.value()
}

#[unsafe(no_mangle)]
pub extern "C" fn main() -> i32 {
    unsafe {
        if dyn_value() == 42 {
            semihost_write0((&raw const OK).cast());
            semihost_exit(0);
        }
        semihost_write0((&raw const FAIL).cast());
        semihost_exit(1);
    }
}
