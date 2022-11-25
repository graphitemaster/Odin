package io

to_reader :: proc "contextless" (s: Stream) -> (r: Reader, ok: bool = true) #optional_ok {
	r.stream = s
	if s.stream_vtable == nil || s.impl_read == nil {
		ok = false
	}
	return
}
to_writer :: proc "contextless" (s: Stream) -> (w: Writer, ok: bool = true) #optional_ok {
	w.stream = s
	if s.stream_vtable == nil || s.impl_write == nil {
		ok = false
	}
	return
}

to_closer :: proc "contextless" (s: Stream) -> (c: Closer, ok: bool = true) #optional_ok {
	c.stream = s
	if s.stream_vtable == nil || s.impl_close == nil {
		ok = false
	}
	return
}
to_flusher :: proc "contextless" (s: Stream) -> (f: Flusher, ok: bool = true) #optional_ok {
	f.stream = s
	if s.stream_vtable == nil || s.impl_flush == nil {
		ok = false
	}
	return
}
to_seeker :: proc "contextless" (s: Stream) -> (seeker: Seeker, ok: bool = true) #optional_ok {
	seeker.stream = s
	if s.stream_vtable == nil || s.impl_seek == nil {
		ok = false
	}
	return
}

to_read_writer :: proc "contextless" (s: Stream) -> (r: Read_Writer, ok: bool = true) #optional_ok {
	r.stream = s
	if s.stream_vtable == nil || s.impl_read == nil || s.impl_write == nil {
		ok = false
	}
	return
}
to_read_closer :: proc "contextless" (s: Stream) -> (r: Read_Closer, ok: bool = true) #optional_ok {
	r.stream = s
	if s.stream_vtable == nil || s.impl_read == nil || s.impl_close == nil {
		ok = false
	}
	return
}
to_read_write_closer :: proc "contextless" (s: Stream) -> (r: Read_Write_Closer, ok: bool = true) #optional_ok {
	r.stream = s
	if s.stream_vtable == nil || s.impl_read == nil || s.impl_write == nil || s.impl_close == nil {
		ok = false
	}
	return
}
to_read_write_seeker :: proc "contextless" (s: Stream) -> (r: Read_Write_Seeker, ok: bool = true) #optional_ok {
	r.stream = s
	if s.stream_vtable == nil || s.impl_read == nil || s.impl_write == nil || s.impl_seek == nil {
		ok = false
	}
	return
}
to_write_flusher :: proc "contextless" (s: Stream) -> (w: Write_Flusher, ok: bool = true) #optional_ok {
	w.stream = s
	if s.stream_vtable == nil || s.impl_write == nil || s.impl_flush == nil {
		ok = false
	}
	return
}
to_write_flush_closer :: proc "contextless" (s: Stream) -> (w: Write_Flush_Closer, ok: bool = true) #optional_ok {
	w.stream = s
	if s.stream_vtable == nil || s.impl_write == nil || s.impl_flush == nil || s.impl_close == nil {
		ok = false
	}
	return
}

to_reader_at :: proc "contextless" (s: Stream) -> (r: Reader_At, ok: bool = true) #optional_ok {
	r.stream = s
	if s.stream_vtable == nil || s.impl_read_at == nil {
		ok = false
	}
	return
}
to_writer_at :: proc "contextless" (s: Stream) -> (w: Writer_At, ok: bool = true) #optional_ok {
	w.stream = s
	if s.stream_vtable == nil || s.impl_write_at == nil {
		ok = false
	}
	return
}
to_reader_from :: proc "contextless" (s: Stream) -> (r: Reader_From, ok: bool = true) #optional_ok {
	r.stream = s
	if s.stream_vtable == nil || s.impl_read_from == nil {
		ok = false
	}
	return
}
to_writer_to :: proc "contextless" (s: Stream) -> (w: Writer_To, ok: bool = true) #optional_ok {
	w.stream = s
	if s.stream_vtable == nil || s.impl_write_to == nil {
		ok = false
	}
	return
}
to_write_closer :: proc "contextless" (s: Stream) -> (w: Write_Closer, ok: bool = true) #optional_ok {
	w.stream = s
	if s.stream_vtable == nil || s.impl_write == nil || s.impl_close == nil {
		ok = false
	}
	return
}
to_write_seeker :: proc "contextless" (s: Stream) -> (w: Write_Seeker, ok: bool = true) #optional_ok {
	w.stream = s
	if s.stream_vtable == nil || s.impl_write == nil || s.impl_seek == nil {
		ok = false
	}
	return
}
