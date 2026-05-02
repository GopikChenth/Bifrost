cmake_minimum_required(VERSION 3.22.1)
project(bifrost_jre_launcher C)

add_library(
    bifrost_jre_launcher
    SHARED
    jre_launcher.c
    utils.c
)

find_library(log-lib log)

target_link_libraries(
    bifrost_jre_launcher
    ${log-lib}
    dl
)
