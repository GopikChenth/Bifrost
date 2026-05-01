cmake_minimum_required(VERSION 3.18.1)
project("bifrost_mte")

add_library(bifrost_mte SHARED bifrost_mte.c)
target_link_libraries(bifrost_mte android log)
