#![no_std]

#[repr(C)]
pub struct Ptr(pub *const i32);

unsafe extern "C" {
    static P: Ptr;
}

#[unsafe(no_mangle)]
pub extern "C" fn get_p_addr() -> *const Ptr {
    &raw const P
}
