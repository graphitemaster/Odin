package json

import "core:mem"
import "core:math/bits"
import "core:runtime"
import "core:strconv"
import "core:strings"

Marshal_Error :: enum {
	None,
	Unsupported_Type,
	Invalid_Data,
}

marshal :: proc(v: any, allocator := context.allocator) -> ([]byte, Marshal_Error) {
	b: strings.Builder;
	strings.init_builder(&b, allocator);

	err := marshal_arg(&b, v);

	if err != .None {
		strings.destroy_builder(&b);
		return nil, err;
	}
	if len(b.buf) == 0 {
		strings.destroy_builder(&b);
		return nil, err;
	}
	return b.buf[:], err;
}


marshal_arg :: proc(b: ^strings.Builder, v: any) -> Marshal_Error {
	if v == nil {
		strings.write_string(b, "null");
		return .None;
	}

	ti := runtime.type_info_base(type_info_of(v.id));
	a := any{v.data, ti.id};

	switch info in ti.variant {
	case runtime.Type_Info_Named:
		unreachable();

	case runtime.Type_Info_Integer:
		buf: [21]byte;
		u: u64;
		switch i in a {
		case i8:      u = u64(i);
		case i16:     u = u64(i);
		case i32:     u = u64(i);
		case i64:     u = u64(i);
		case int:     u = u64(i);
		case u8:      u = u64(i);
		case u16:     u = u64(i);
		case u32:     u = u64(i);
		case u64:     u = u64(i);
		case uint:    u = u64(i);
		case uintptr: u = u64(i);

		case i16le: u = u64(i);
		case i32le: u = u64(i);
		case i64le: u = u64(i);
		case u16le: u = u64(i);
		case u32le: u = u64(i);
		case u64le: u = u64(i);

		case i16be: u = u64(i);
		case i32be: u = u64(i);
		case i64be: u = u64(i);
		case u16be: u = u64(i);
		case u32be: u = u64(i);
		case u64be: u = u64(i);
		}

		s := strconv.append_bits(buf[:], u, 10, info.signed, 8*ti.size, "0123456789", nil);
		strings.write_string(b, s);


	case runtime.Type_Info_Rune:
		r := a.(rune);
		strings.write_byte(b, '"');
		strings.write_escaped_rune(b, r, '"', true);
		strings.write_byte(b, '"');

	case runtime.Type_Info_Float:
		val: f64;
		switch f in a {
		case f16: val = f64(f);
		case f32: val = f64(f);
		case f64: val = f64(f);
		}

		buf: [386]byte;

		str := strconv.append_float(buf[1:], val, 'f', 2*ti.size, 8*ti.size);
		s := buf[:len(str)+1];
		if s[1] == '+' || s[1] == '-' {
			s = s[1:];
		} else {
			s[0] = '+';
		}
		if s[0] == '+' {
			s = s[1:];
		}

		strings.write_string(b, string(s));

	case runtime.Type_Info_Complex:
		return .Unsupported_Type;

	case runtime.Type_Info_Quaternion:
		return .Unsupported_Type;

	case runtime.Type_Info_String:
		switch s in a {
		case string:  strings.write_quoted_string(b, s);
		case cstring: strings.write_quoted_string(b, string(s));
		}

	case runtime.Type_Info_Boolean:
		val: bool;
		switch b in a {
		case bool: val = bool(b);
		case b8:   val = bool(b);
		case b16:  val = bool(b);
		case b32:  val = bool(b);
		case b64:  val = bool(b);
		}
		strings.write_string(b, val ? "true" : "false");

	case runtime.Type_Info_Any:
		return .Unsupported_Type;

	case runtime.Type_Info_Type_Id:
		return .Unsupported_Type;

	case runtime.Type_Info_Pointer:
		return .Unsupported_Type;

	case runtime.Type_Info_Multi_Pointer:
		return .Unsupported_Type;

	case runtime.Type_Info_Procedure:
		return .Unsupported_Type;

	case runtime.Type_Info_Tuple:
		return .Unsupported_Type;

	case runtime.Type_Info_Enumerated_Array:
		return .Unsupported_Type;

	case runtime.Type_Info_Simd_Vector:
		return .Unsupported_Type;

	case runtime.Type_Info_Relative_Pointer:
		return .Unsupported_Type;

	case runtime.Type_Info_Relative_Slice:
		return .Unsupported_Type;

	case runtime.Type_Info_Array:
		strings.write_byte(b, '[');
		for i in 0..<info.count {
			if i > 0 { strings.write_string(b, ", "); }

			data := uintptr(v.data) + uintptr(i*info.elem_size);
			marshal_arg(b, any{rawptr(data), info.elem.id});
		}
		strings.write_byte(b, ']');

	case runtime.Type_Info_Dynamic_Array:
		strings.write_byte(b, '[');
		array := cast(^mem.Raw_Dynamic_Array)v.data;
		for i in 0..<array.len {
			if i > 0 { strings.write_string(b, ", "); }

			data := uintptr(array.data) + uintptr(i*info.elem_size);
			marshal_arg(b, any{rawptr(data), info.elem.id});
		}
		strings.write_byte(b, ']');

	case runtime.Type_Info_Slice:
		strings.write_byte(b, '[');
		slice := cast(^mem.Raw_Slice)v.data;
		for i in 0..<slice.len {
			if i > 0 { strings.write_string(b, ", "); }

			data := uintptr(slice.data) + uintptr(i*info.elem_size);
			marshal_arg(b, any{rawptr(data), info.elem.id});
		}
		strings.write_byte(b, ']');

	case runtime.Type_Info_Map:
		m := (^mem.Raw_Map)(v.data);

		strings.write_byte(b, '{');
		if m != nil {
			if info.generated_struct == nil {
				return .Unsupported_Type;
			}
			entries    := &m.entries;
			gs         := runtime.type_info_base(info.generated_struct).variant.(runtime.Type_Info_Struct);
			ed         := runtime.type_info_base(gs.types[1]).variant.(runtime.Type_Info_Dynamic_Array);
			entry_type := ed.elem.variant.(runtime.Type_Info_Struct);
			entry_size := ed.elem_size;

			for i in 0..<entries.len {
				if i > 0 { strings.write_string(b, ", "); }

				data := uintptr(entries.data) + uintptr(i*entry_size);
				key   := rawptr(data + entry_type.offsets[2]);
				value := rawptr(data + entry_type.offsets[3]);

				marshal_arg(b, any{key, info.key.id});
				strings.write_string(b, ": ");
				marshal_arg(b, any{value, info.value.id});
			}
		}
		strings.write_byte(b, '}');

	case runtime.Type_Info_Struct:
		strings.write_byte(b, '{');
		for name, i in info.names {
			if i > 0 { strings.write_string(b, ", "); }
			strings.write_quoted_string(b, name);
			strings.write_string(b, ": ");

			id := info.types[i].id;
			data := rawptr(uintptr(v.data) + info.offsets[i]);
			marshal_arg(b, any{data, id});
		}
		strings.write_byte(b, '}');

	case runtime.Type_Info_Union:
		tag_ptr := uintptr(v.data) + info.tag_offset;
		tag_any := any{rawptr(tag_ptr), info.tag_type.id};

		tag: i64 = -1;
		switch i in tag_any {
		case u8:   tag = i64(i);
		case i8:   tag = i64(i);
		case u16:  tag = i64(i);
		case i16:  tag = i64(i);
		case u32:  tag = i64(i);
		case i32:  tag = i64(i);
		case u64:  tag = i64(i);
		case i64:  tag = i64(i);
		case: panic("Invalid union tag type");
		}

		if v.data == nil || tag == 0 {
			strings.write_string(b, "null");
		} else {
			id := info.variants[tag-1].id;
			marshal_arg(b, any{v.data, id});
		}

	case runtime.Type_Info_Enum:
		return marshal_arg(b, any{v.data, info.base.id});

	case runtime.Type_Info_Bit_Set:
		is_bit_set_different_endian_to_platform :: proc(ti: ^runtime.Type_Info) -> bool {
			if ti == nil {
				return false;
			}
			t := runtime.type_info_base(ti);
			#partial switch info in t.variant {
			case runtime.Type_Info_Integer:
				switch info.endianness {
				case .Platform: return false;
				case .Little:   return ODIN_ENDIAN != "little";
				case .Big:      return ODIN_ENDIAN != "big";
				}
			}
			return false;
		}

		bit_data: u64;
		bit_size := u64(8*ti.size);

		do_byte_swap := is_bit_set_different_endian_to_platform(info.underlying);

		switch bit_size {
		case  0: bit_data = 0;
		case  8:
			x := (^u8)(v.data)^;
			bit_data = u64(x);
		case 16:
			x := (^u16)(v.data)^;
			if do_byte_swap {
				x = bits.byte_swap(x);
			}
			bit_data = u64(x);
		case 32:
			x := (^u32)(v.data)^;
			if do_byte_swap {
				x = bits.byte_swap(x);
			}
			bit_data = u64(x);
		case 64:
			x := (^u64)(v.data)^;
			if do_byte_swap {
				x = bits.byte_swap(x);
			}
			bit_data = u64(x);
		case: panic("unknown bit_size size");
		}
		strings.write_u64(b, bit_data);


		return .Unsupported_Type;
	}

	return .None;
}
