package libc

// 7.5 Errors

foreign import libc "system:c"

// C11 standard only requires the definition of:
//	EDOM,
//	EILSEQ
//	ERANGE
when ODIN_OS == "linux" || ODIN_OS == "freebsd" {
	@(private="file")
	@(default_calling_convention="c")
	foreign libc {
		@(link_name="__libc_errno_location")
		_get_errno :: proc() -> ^int ---;
	}

	EDOM   :: 33;
	EILSEQ :: 84;
	ERANGE :: 34;
}

when ODIN_OS == "windows" {
	@(private="file")
	@(default_calling_convention="c")
	foreign libc {
		@(link_name="_errno")
		_get_errno :: proc() -> ^int ---;
	}

	EDOM   :: 33;
	EILSEQ :: 42;
	ERANGE :: 34;
}

// Odin has no way to make an identifier "errno" behave as a function call to
// read the value, or to produce an lvalue such that you can assign a different
// error value to errno. To work around this, just expose it as a function like
// it actually is.
errno :: #force_inline proc() -> ^int {
	return _get_errno();
}
