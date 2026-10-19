// Minimal Godot 4.4+ C-interface adapter; no godot-cpp or engine types in the
// core.
#include "ember_core.h"
#include "gdextension_interface.h"
namespace {
GDExtensionClassLibraryPtr library;
GDExtensionInterfaceGetProcAddress proc;
GDExtensionInterfaceClassdbConstructObject2 construct;
GDExtensionInterfaceObjectSetInstance set_instance;
GDExtensionInterfaceObjectMethodBindPtrcall method_ptrcall;
GDExtensionMethodBindPtr notification;
GDExtensionVariantFromTypeConstructorFunc from_int;
GDExtensionTypeFromVariantConstructorFunc to_int;
GDExtensionPtrDestructor destroy_name, destroy_string;
// Godot's pinned 64-bit ABI stores String/StringName in one aligned pointer.
struct alignas(8) Small {
  unsigned char bytes[8];
};
Small names[9]{}, empty_string{};
struct Instance {
  EC_Handle *core;
} instances[32]{};
template <class T> T load(const char *name) {
  return reinterpret_cast<T>(proc(name));
}
GDExtensionObjectPtr create(void *, GDExtensionBool notify) {
  for (auto &instance : instances)
    if (!instance.core) {
      instance.core = ec_v1_create(EC_ABI_V1, EC_ROLE_HOST, 1);
      if (!instance.core)
        return nullptr;
      auto object = construct(&names[1]);
      if (!object) {
        ec_v1_destroy(instance.core);
        instance.core = nullptr;
        return nullptr;
      }
      set_instance(object, &names[0], &instance);
      if (notify) {
        int64_t what = 0;
        GDExtensionBool reversed = 0;
        const void *args[] = {&what, &reversed};
        method_ptrcall(notification, object, args, nullptr);
      }
      return object;
    }
  return nullptr;
}
void release(void *, GDExtensionClassInstancePtr ptr) {
  auto *instance = static_cast<Instance *>(ptr);
  ec_v1_destroy(instance->core);
  instance->core = nullptr;
}
void call(void *, GDExtensionClassInstancePtr ptr,
          const GDExtensionConstVariantPtr *args, GDExtensionInt count,
          GDExtensionVariantPtr result, GDExtensionCallError *error) {
  int64_t output = EC_ERR_ARGUMENT;
  if (count == 3 && ptr) {
    int64_t values[3]{};
    for (uint32_t i = 0; i < 3; i++)
      to_int(&values[i], const_cast<void *>(args[i]));
    output =
        ec_v1_command(static_cast<Instance *>(ptr)->core, int32_t(values[0]),
                      int32_t(values[1]), int32_t(values[2]));
    error->error = GDEXTENSION_CALL_OK;
  } else
    error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;
  from_int(result, &output);
}
void ptrcall(void *, GDExtensionClassInstancePtr ptr,
             const GDExtensionConstTypePtr *args, GDExtensionTypePtr result) {
  *static_cast<int64_t *>(result) =
      ec_v1_command(static_cast<Instance *>(ptr)->core,
                    int32_t(*static_cast<const int64_t *>(args[0])),
                    int32_t(*static_cast<const int64_t *>(args[1])),
                    int32_t(*static_cast<const int64_t *>(args[2])));
}
void initialize(void *, GDExtensionInitializationLevel level) {
  if (level != GDEXTENSION_INITIALIZATION_SCENE)
    return;
  auto new_name = load<GDExtensionInterfaceStringNameNewWithUtf8Chars>(
      "string_name_new_with_utf8_chars");
  const char *labels[] = {
      "EmberCoreNative", "RefCounted",  "command", "operation", "a", "b", "",
      "Object",          "notification"};
  for (uint32_t i = 0; i < 9; i++)
    new_name(&names[i], labels[i]);
  load<GDExtensionInterfaceStringNewWithUtf8Chars>(
      "string_new_with_utf8_chars")(&empty_string, "");
  notification = load<GDExtensionInterfaceClassdbGetMethodBind>(
      "classdb_get_method_bind")(&names[7], &names[8], 4023243586);
  GDExtensionClassCreationInfo4 info{};
  info.is_exposed = 1;
  info.create_instance_func = create;
  info.free_instance_func = release;
  load<GDExtensionInterfaceClassdbRegisterExtensionClass4>(
      "classdb_register_extension_class4")(library, &names[0], &names[1],
                                           &info);
  GDExtensionPropertyInfo returns{};
  returns.type = GDEXTENSION_VARIANT_TYPE_INT;
  returns.name = &names[6];
  returns.class_name = &names[6];
  returns.hint_string = &empty_string;
  returns.usage = 6;
  GDExtensionPropertyInfo arguments[3] = {returns, returns, returns};
  for (uint32_t i = 0; i < 3; i++)
    arguments[i].name = &names[3 + i];
  GDExtensionClassMethodArgumentMetadata metadata[3] = {
      GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64,
      GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64,
      GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64};
  GDExtensionClassMethodInfo method{};
  method.name = &names[2];
  method.call_func = call;
  method.ptrcall_func = ptrcall;
  method.method_flags = 1;
  method.has_return_value = 1;
  method.return_value_info = &returns;
  method.return_value_metadata =
      GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64;
  method.argument_count = 3;
  method.arguments_info = arguments;
  method.arguments_metadata = metadata;
  load<GDExtensionInterfaceClassdbRegisterExtensionClassMethod>(
      "classdb_register_extension_class_method")(library, &names[0], &method);
}
void deinitialize(void *, GDExtensionInitializationLevel level) {
  if (level != GDEXTENSION_INITIALIZATION_SCENE)
    return;
  load<GDExtensionInterfaceClassdbUnregisterExtensionClass>(
      "classdb_unregister_extension_class")(library, &names[0]);
  for (auto &name : names)
    destroy_name(&name);
  destroy_string(&empty_string);
}
} // namespace
extern "C" EC_API GDExtensionBool ember_core_extension_init(
    GDExtensionInterfaceGetProcAddress get_proc, GDExtensionClassLibraryPtr lib,
    GDExtensionInitialization *init) {
  proc = get_proc;
  library = lib;
  construct = load<GDExtensionInterfaceClassdbConstructObject2>(
      "classdb_construct_object2");
  set_instance =
      load<GDExtensionInterfaceObjectSetInstance>("object_set_instance");
  method_ptrcall = load<GDExtensionInterfaceObjectMethodBindPtrcall>(
      "object_method_bind_ptrcall");
  from_int = load<GDExtensionInterfaceGetVariantFromTypeConstructor>(
      "get_variant_from_type_constructor")(GDEXTENSION_VARIANT_TYPE_INT);
  to_int = load<GDExtensionInterfaceGetVariantToTypeConstructor>(
      "get_variant_to_type_constructor")(GDEXTENSION_VARIANT_TYPE_INT);
  auto destructor = load<GDExtensionInterfaceVariantGetPtrDestructor>(
      "variant_get_ptr_destructor");
  destroy_name = destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
  destroy_string = destructor(GDEXTENSION_VARIANT_TYPE_STRING);
  init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
  init->initialize = initialize;
  init->deinitialize = deinitialize;
  init->userdata = nullptr;
  return 1;
}
