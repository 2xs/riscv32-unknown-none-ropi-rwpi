#![no_std]

#[repr(C)]
pub struct Ptr(pub *const i32);

unsafe impl Sync for Ptr {}

#[unsafe(no_mangle)]
pub static TARGET: i32 = 23;

#[unsafe(no_mangle)]
pub static P: Ptr = Ptr(&raw const TARGET);
