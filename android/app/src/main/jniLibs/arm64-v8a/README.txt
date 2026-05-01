Place bundled Termux-derived OpenJDK 21 native files here for Bifröst.

Expected files:
- libbifrost_java.so
  - copy from Termux OpenJDK 21: bin/java
- libandroid-shmem.so
  - copy from Termux usr/lib
- libz.so.1
  - copy from Termux usr/lib if the launcher/runtime requires it at startup

Notes:
- The launcher must remain Android-native and use /system/bin/linker64.
- Do not use a desktop Linux or Windows Java binary here.
- Additional libraries may be required after smoke-test validation.
