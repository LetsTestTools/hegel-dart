import '../ffi/hegel_bindings.g.dart';

abstract final class HegelLabel {
  static const int list = 1;
  static const int listElement = 2;
  static const int set = 3;
  static const int setElement = 4;
  static const int map = 5;
  static const int mapEntry = 6;
  static const int tuple = 7;
  static const int oneOf = 8;
  static const int optional = 9;
  static const int fixedDict = 10;
  static const int flatMap = 11;
  static const int filter = 12;
  static const int mapped = 13;
  static const int sampledFrom = 14;
  static const int enumVariant = 15;
}
