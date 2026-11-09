// Vibration for Lumi & the Hollow on Android, called from the game through JNI.
//
// The app has no Java of its own (it is a NativeActivity), so the Vibrator
// service is reached the long way: the activity object raylib's native glue
// keeps, getSystemService("vibrator"), and VibrationEffect.createOneShot. The
// lookups are done once and kept as global references.
//
// The game runs on the glue's own native thread, which the JVM does not know
// about until it is attached; oddy_haptics_shutdown() detaches it again before
// the thread ends, which ART insists on.

#include <jni.h>
#include <android_native_app_glue.h>

struct android_app *GetAndroidApp(void); // raylib

static JNIEnv *env;
static int attached;
static int ready; // 0 not tried yet, 1 working, -1 no vibrator
static jobject vibrator;
static jclass effect_class;
static jmethodID create_one_shot;
static jmethodID vibrate;

static int failed(void) {
	if ((*env)->ExceptionCheck(env)) {
		(*env)->ExceptionClear(env);
		return 1;
	}
	return 0;
}

static int setup(void) {
	struct android_app *app = GetAndroidApp();
	if (!app || !app->activity) return 0;
	JavaVM *vm = app->activity->vm;
	if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
		if ((*vm)->AttachCurrentThread(vm, &env, NULL) != JNI_OK) return 0;
		attached = 1;
	}

	jobject activity = app->activity->clazz;
	jclass context = (*env)->GetObjectClass(env, activity);
	jmethodID get_service = (*env)->GetMethodID(env, context, "getSystemService",
		"(Ljava/lang/String;)Ljava/lang/Object;");
	jstring name = (*env)->NewStringUTF(env, "vibrator");
	jobject service = (*env)->CallObjectMethod(env, activity, get_service, name);
	(*env)->DeleteLocalRef(env, name);
	if (failed() || !service) return 0;
	vibrator = (*env)->NewGlobalRef(env, service);

	jclass vibrator_class = (*env)->GetObjectClass(env, service);
	vibrate = (*env)->GetMethodID(env, vibrator_class, "vibrate", "(Landroid/os/VibrationEffect;)V");
	jclass effect = (*env)->FindClass(env, "android/os/VibrationEffect");
	if (failed() || !effect || !vibrate) return 0;
	effect_class = (*env)->NewGlobalRef(env, effect);
	create_one_shot = (*env)->GetStaticMethodID(env, effect_class, "createOneShot",
		"(JI)Landroid/os/VibrationEffect;");
	return !failed() && create_one_shot;
}

// One short buzz: `ms` long, `amplitude` 1..255.
void oddy_vibrate(int ms, int amplitude) {
	if (ready == 0) ready = setup() ? 1 : -1;
	if (ready != 1) return;
	jobject effect = (*env)->CallStaticObjectMethod(env, effect_class, create_one_shot,
		(jlong)ms, (jint)amplitude);
	if (failed() || !effect) return;
	(*env)->CallVoidMethod(env, vibrator, vibrate, effect);
	failed();
	(*env)->DeleteLocalRef(env, effect);
}

void oddy_haptics_shutdown(void) {
	struct android_app *app = GetAndroidApp();
	if (ready == 1) {
		(*env)->DeleteGlobalRef(env, vibrator);
		(*env)->DeleteGlobalRef(env, effect_class);
	}
	if (attached && app && app->activity) {
		JavaVM *vm = app->activity->vm;
		(*vm)->DetachCurrentThread(vm);
	}
	ready = 0;
	attached = 0;
}
