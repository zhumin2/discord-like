/// 客户端版本：CI 构建（打 tag）时通过 --dart-define 注入（如 v1.3.1）。
/// 本地 flutter run/build 未注入时为 dev。
const String appVersion = String.fromEnvironment(
  'CHORD_VERSION',
  defaultValue: 'dev',
);
