//+build windows
//+private
package thread

import "core:runtime"
import sync "core:sync/sync2"
import win32 "core:sys/windows"

Thread_Os_Specific :: struct {
	win32_thread:    win32.HANDLE,
	win32_thread_id: win32.DWORD,
	done: bool, // see note in `is_done`
}

_thread_priority_map := [Thread_Priority]i32{
	.Normal = 0,
	.Low = -2,
	.High = +2,
};

_create :: proc(procedure: Thread_Proc, priority := Thread_Priority.Normal) -> ^Thread {
	win32_thread_id: win32.DWORD;

	__windows_thread_entry_proc :: proc "stdcall" (t_: rawptr) -> win32.DWORD {
		t := (^Thread)(t_);
		context = t.init_context.? or_else runtime.default_context();

		t.procedure(t);

		if t.init_context == nil {
			if context.temp_allocator.data == &runtime.global_default_temp_allocator_data {
				runtime.default_temp_allocator_destroy(auto_cast context.temp_allocator.data);
			}
		}

		sync.atomic_store(&t.done, true);
		return 0;
	}


	thread := new(Thread);
	if thread == nil {
		return nil;
	}
	thread.creation_allocator = context.allocator;

	win32_thread := win32.CreateThread(nil, 0, __windows_thread_entry_proc, thread, win32.CREATE_SUSPENDED, &win32_thread_id);
	if win32_thread == nil {
		free(thread, thread.creation_allocator);
		return nil;
	}
	thread.procedure       = procedure;
	thread.win32_thread    = win32_thread;
	thread.win32_thread_id = win32_thread_id;
	thread.init_context = context;

	ok := win32.SetThreadPriority(win32_thread, _thread_priority_map[priority]);
	assert(ok == true);

	return thread;
}

_start :: proc(thread: ^Thread) {
	win32.ResumeThread(thread.win32_thread);
}

_is_done :: proc(using thread: ^Thread) -> bool {
	// NOTE(tetra, 2019-10-31): Apparently using wait_for_single_object and
	// checking if it didn't time out immediately, is not good enough,
	// so we do it this way instead.
	return sync.atomic_load(&done);
}

_join :: proc(using thread: ^Thread) {
	if win32_thread != win32.INVALID_HANDLE {
		win32.WaitForSingleObject(win32_thread, win32.INFINITE);
		win32.CloseHandle(win32_thread);
		win32_thread = win32.INVALID_HANDLE;
	}
}

_join_multiple :: proc(threads: ..^Thread) {
	MAXIMUM_WAIT_OBJECTS :: 64;

	handles: [MAXIMUM_WAIT_OBJECTS]win32.HANDLE;

	for k := 0; k < len(threads); k += MAXIMUM_WAIT_OBJECTS {
		count := min(len(threads) - k, MAXIMUM_WAIT_OBJECTS);
		j := 0;
		for i in 0..<count {
			handle := threads[i+k].win32_thread;
			if handle != win32.INVALID_HANDLE {
				handles[j] = handle;
				j += 1;
			}
		}
		win32.WaitForMultipleObjects(u32(j), &handles[0], true, win32.INFINITE);
	}

	for t in threads {
		win32.CloseHandle(t.win32_thread);
		t.win32_thread = win32.INVALID_HANDLE;
	}
}

_destroy :: proc(thread: ^Thread) {
	_join(thread);
	free(thread, thread.creation_allocator);
}

_terminate :: proc(using thread : ^Thread, exit_code: int) {
	win32.TerminateThread(win32_thread, u32(exit_code));
}

_yield :: proc() {
	win32.SwitchToThread();
}

