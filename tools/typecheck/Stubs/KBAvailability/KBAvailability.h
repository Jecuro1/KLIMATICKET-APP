// Availability domains for the Linux type-check harness (Swift "CustomAvailability").
//
// Apple declarations introduced after the deployment target (iOS 26.0) carry
// `@available(iOS_26_<minor>)` in the stubs; tools/typecheck/preprocess.py rewrites
// `#available(iOS 26.x, *)` / `@available(iOS 26.x, *)` in app code to the
// matching domains, so using a 26.1+ API without a check is an error, exactly
// like in Xcode with IPHONEOS_DEPLOYMENT_TARGET = 26.0.
//
// KBAppOnly marks API that is `@available(iOSApplicationExtension, unavailable)`
// (e.g. UIApplication.shared). It is always available in the app target and
// unavailable when type-checking the widget extension (-DKB_APP_EXTENSION),
// mirroring APPLICATION_EXTENSION_API_ONLY = YES.
#include <availability_domain.h>

static inline int __kb_availability_query(void) { return 1; }

CLANG_DYNAMIC_AVAILABILITY_DOMAIN(iOS_26_1, __kb_availability_query);
CLANG_DYNAMIC_AVAILABILITY_DOMAIN(iOS_26_2, __kb_availability_query);
CLANG_DYNAMIC_AVAILABILITY_DOMAIN(iOS_26_3, __kb_availability_query);
CLANG_DYNAMIC_AVAILABILITY_DOMAIN(iOS_26_4, __kb_availability_query);
CLANG_DYNAMIC_AVAILABILITY_DOMAIN(iOS_26_5, __kb_availability_query);

#ifdef KB_APP_EXTENSION
CLANG_DISABLED_AVAILABILITY_DOMAIN(KBAppOnly);
#else
CLANG_ALWAYS_ENABLED_AVAILABILITY_DOMAIN(KBAppOnly);
#endif
