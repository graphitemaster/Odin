package libc

foreign import libc "system:c"

// 7.4 Character handling

@(default_calling_convention="c")
foreign libc {
	// 7.4.1 Character classification functions
	isalnum  :: proc(c: int) -> int ---;
	isalpha  :: proc(c: int) -> int ---;
	isblank  :: proc(c: int) -> int ---;
	iscntrl  :: proc(c: int) -> int ---;
	isdigit  :: proc(c: int) -> int ---;
	isgraph  :: proc(c: int) -> int ---;
	islower  :: proc(c: int) -> int ---;
	isprint  :: proc(c: int) -> int ---;
	ispunct  :: proc(c: int) -> int ---;
	isspace  :: proc(c: int) -> int ---;
	isupper  :: proc(c: int) -> int ---;
	isxdigit :: proc(c: int) -> int ---;

	// 7.4.2 Character case mapping functions
	tolower  :: proc(c: int) -> int ---;
	toupper  :: proc(c: int) -> int ---;
}
