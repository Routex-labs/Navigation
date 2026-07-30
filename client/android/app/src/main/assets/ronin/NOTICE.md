# RoNIN Android 실험 모델

- 원 논문: *RoNIN: Robust Neural Inertial Navigation in the Wild*
- 공식 코드: https://github.com/Sachini/ronin
- 공식 데이터·사전학습 모델: https://doi.org/10.20383/102.0543
- 사용 모델: 공식 `ronin_tcn_checkpoint.pt`를 ONNX(opset 17)로 변환
- 입력: 세계 좌표계 200Hz `[gyro_x, gyro_y, gyro_z, accel_x, accel_y, accel_z]`
- 출력: 200Hz 수평 속도 `[velocity_x, velocity_y]`
- ONNX SHA-256:
  `55e45a039cd9cf72688a75965771299549838fcafba35339291406eb0aeeb950`

이 모델은 `LICENSE.txt`에 따라 비상업적 과학 연구·교육 목적으로만 사용할 수
있다. 앱의 Android 디버그 비교 경로에서만 사용하며 제품 위치·길찾기 결과에는
반영하지 않는다.
