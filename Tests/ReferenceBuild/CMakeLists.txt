#----------------------------------------------------------------------------------------------------------------------
#
#----------------------------------------------------------------------------------------------------------------------
cmake_minimum_required(VERSION 3.20)

project(ReferenceBuild LANGUAGES CXX)

add_library(A_Library STATIC
    Reference.cpp
)

add_library(B_Library
    Reference.cpp
)

add_library(C_Library
    Reference.cpp
)
