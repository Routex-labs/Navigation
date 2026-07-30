# ONNX Runtime(RoNIN 비교 경로)의 네이티브 코드는 JNI FindClass/GetMethodID로
# ai.onnxruntime 클래스를 **이름으로** 찾는다. R8이 이름을 바꾸면 FindClass가
# null을 돌려주고, 곧바로 GetMethodID에서 런타임이 abort한다:
#
#   JNI DETECTED ERROR IN APPLICATION: java_class == null
#     in call to GetMethodID
#     from boolean[] ai.onnxruntime.OrtSession.run(...)
#   #06 convertToTensorInfo  #07 convertOrtValueToONNXValue
#
# release 빌드에서만 R8이 돌기 때문에 debug로는 재현되지 않는다. 실측에서는
# 걷기 시작하고 첫 추론이 도는 시점(약 5걸음)에 앱이 죽었다.
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**
