package main

/*
#ifdef __cplusplus
extern "C" {
#endif

void hv2ray_kernel_log(const char* msg);

#ifdef __cplusplus
}
#endif
*/
import "C"

func WriteLog(msg string) {
	C.hv2ray_kernel_log(C.CString(msg))
}

//export StartV2RayKernel
func StartV2RayKernel(configBytes *C.char) *C.char {
	config := C.GoString(configBytes)
	err := DoStart(config)
	if err != nil {
		WriteLog(err.Error())
		return C.CString(err.Error())
	}

	if GLOBAL_INSTANCE == nil {
		DoClose()
		return C.CString("Global instance is nil after a successful start.")
	}

	return nil
}

//export CloseV2RayKernel
func CloseV2RayKernel() {
	DoClose()
}
