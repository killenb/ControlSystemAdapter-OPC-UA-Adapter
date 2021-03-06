cmake_minimum_required(VERSION 2.8.0)

project(ControlSystem-OPCUA_Adapter)

include(ExternalProject)
##########################################################################################################
## Hard package dependencies
##########################################################################################################

find_package(Boost COMPONENTS system filesystem thread chrono unit_test_framework REQUIRED)
find_package(LibXml2 REQUIRED)
find_package(PythonInterp REQUIRED)

#Do not put the ControlSystemAdapter as required. We will install it if it is not found.
find_package(ChimeraTK-ControlSystemAdapter 0.2)

#Install the ControlSystemAdapter if it is not pre-installed
if( NOT ChimeraTK-ControlSystemAdapter_FOUND )
  message("Installing ChimeraTK-ControlSystemAdapter as external dependency inside the build directory.")
  message("You will not be able to make a proper installation of the OPCUA_Adapter. Only use this for testing and development.\n")
  ExternalProject_Add(external-ChimeraTK-ControlSystemAdapter
    GIT_REPOSITORY "https://github.com/ChimeraTK/ControlSystemAdapter.git"
    #When creationg a tag, base it on a tag of the ControlSystemAdapter so it stays stable
    #GIT_TAG "00.02.00"
    CMAKE_ARGS "-DCMAKE_INSTALL_PREFIX=${CMAKE_BINARY_DIR}/ChimeraTK"
    )
  #FIXME: Find a better name for this variable
  set(USE_SELFINSTALLED_ControlSystemAdapter TRUE)
  #As the external project is only condifured in the build step, we have to cheat the
  #configuration here which otherwise is provided by find_package.
  #Attention: This is a hack and can become inconsistent with the read config.
  #
  #ChimeraTK-ControlSystemAdapter_CXX_FLAGS currently only provides C++11, which is used anyway
  #ChimeraTK-ControlSystemAdapter_LINKER_FLAGS provides the rpath, not needed for testing
  #
  #We leave out the boost flags as the OPCUA_Adapter uses them itself
  set(ChimeraTK-ControlSystemAdapter_INCLUDE_DIRS ${CMAKE_BINARY_DIR}/ChimeraTK/include)
  set(ChimeraTK-ControlSystemAdapter_LIBRARY_DIRS ${CMAKE_BINARY_DIR}/ChimeraTK/lib)
  set(ChimeraTK-ControlSystemAdapter_LIBRARIES ChimeraTK-ControlSystemAdapter)
endif()

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${ChimeraTK-ControlSystemAdapter_CXX_FLAGS}")
link_directories(${ChimeraTK-ControlSystemAdapter_LIBRARY_DIRS})

##########################################################################################################
## Compiler specific stuff
##########################################################################################################

if(CMAKE_COMPILER_IS_GNUCC OR "x${CMAKE_C_COMPILER_ID}" STREQUAL "xClang")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11")
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=c99")
  set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -g")
  set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)

  add_definitions(-fPIC)
  add_definitions(-fprofile-arcs)
  add_definitions(-ftest-coverage)
endif()


##########################################################################################################
## Includes, Link dirs und Quellcode
##########################################################################################################

set(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_PREFIX}/lib")

include_directories(${CMAKE_SOURCE_DIR}/include)
include_directories(SYSTEM ${CMAKE_SOURCE_DIR}/include/open62541/)
include_directories(SYSTEM ${ChimeraTK-ControlSystemAdapter_INCLUDE_DIRS})
include_directories(${CMAKE_SOURCE_DIR}/examples/)
include_directories(SYSTEM ${LIBXML2_INCLUDE_DIR})
link_directories(${CMAKE_SOURCE_DIR}/lib)
link_directories(${LIBXML2_LIBRARIES})

 
                    
set(objectSources  ${CMAKE_SOURCE_DIR}/src/ua_mapped_class.cpp
                   ${CMAKE_SOURCE_DIR}/src/ua_proxies.cpp
                   ${CMAKE_SOURCE_DIR}/src/ipc_managed_object.cpp
                   ${CMAKE_SOURCE_DIR}/src/ipc_manager.cpp
                   ${CMAKE_SOURCE_DIR}/src/ipc_task.cpp
                   ${CMAKE_SOURCE_DIR}/src/ControlSystemAdapterOPCUA.cpp
                   ${CMAKE_SOURCE_DIR}/src/xml_file_handler.cpp
                   ${CMAKE_SOURCE_DIR}/src/mtca_processvariable.cpp
                   ${CMAKE_SOURCE_DIR}/src/mtca_uaadapter.cpp
                   
                   # Example HelperClass
                   ${CMAKE_SOURCE_DIR}/examples/runtimeValueGenerator.cpp
)

# Create the target directory for model initializers, open62541 and ControlSystemAdapter libraries/headers
file(MAKE_DIRECTORY "${PROJECT_BINARY_DIR}/src_generated")
include_directories(${PROJECT_BINARY_DIR}/src_generated/)

##########################################################################################################
## Optionen
##########################################################################################################

## Project specific options
option(ENABLE_BUILDMODEL      "Create model from XML description"      ON)

## Code quality control options
option(ENABLE_COVERAGE        "Enable coverage stats for server build" ON)
option(BUILD_STATIC_ANALYSIS  "Instead of building a binary, perform a static code analysis using clangs analyzer." OFF)
option(ENABLE_LINTING         "Enables running the cppcheck static analyzer prior to compilation." OFF)
option(ENABLE_UNIT_TESTS      "Compile and run unit tests." ON)

if(ENABLE_BUILDMODEL)
  set(MODEL_XML_FILE "templatemodel.xml" CACHE STRING "Namespace definition XML file for MTCA Model")
  
  list(APPEND objectSources ${PROJECT_BINARY_DIR}/src_generated/mtca_namespaceinit_generated.c)
else()
  include_directories(${CMAKE_SOURCE_DIR}/include/model_prebuilt/)
  list(APPEND objectSources ${CMAKE_SOURCE_DIR}/include/model_prebuilt/mtca_namespaceinit_generated.c)
  
  include_directories(${PROJECT_SOURCE_DIR}/include/open62541/src/)
  include_directories(${PROJECT_SOURCE_DIR}/include/open62541/deps/)
endif()

if(ENABLE_COVERAGE)
  set(CMAKE_BUILD_TYPE DEBUG)
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fprofile-arcs -ftest-coverage")
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fprofile-arcs -ftest-coverage")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fprofile-arcs -ftest-coverage")
  set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -fprofile-arcs -ftest-coverage")
endif()

if(ENABLE_UNIT_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

if(BUILD_STATIC_ANALYSIS)
  set(CMAKE_C_COMPILER   ccc-analyzer)
  set(CMAKE_CXX_COMPILER ccc-analyzer)
  add_definitions(-o ${PROJECT_BINARY_DIR}/static-analysis})
endif()

##########################################################################################################
## Object and shared library compilation required by tests and examples
##########################################################################################################

## Config File
configure_file (
  "${PROJECT_SOURCE_DIR}/include/csa_config.h.in"
  "${PROJECT_BINARY_DIR}/src_generated/csa_config.h"
  )

## Object Files
add_library(mtca_objects OBJECT ${objectSources})
if(USE_SELFINSTALLED_ControlSystemAdapter)
  ADD_DEPENDENCIES(mtca_objects external-ChimeraTK-ControlSystemAdapter) 
endif()

## Early declaration due to the requirement to run the dependencies update prior to building
## Create shared lib
add_library(ControlSystemAdapterOPCUA SHARED $<TARGET_OBJECTS:mtca_objects>)
target_link_libraries(ControlSystemAdapterOPCUA open62541)
target_link_libraries(ControlSystemAdapterOPCUA ${ChimeraTK-ControlSystemAdapter_LIBRARIES})
target_link_libraries(ControlSystemAdapterOPCUA pthread)
target_link_libraries(ControlSystemAdapterOPCUA dl)
target_link_libraries(ControlSystemAdapterOPCUA
  ${Boost_FILESYSTEM_LIBRARY}
  ${Boost_SYSTEM_LIBRARY}
  ${Boost_THREAD_LIBRARY}
  ${Boost_CHRONO_LIBRARY}
  ${Boost_UNIT_TEST_FRAMEWORK_LIBRARY}
)
target_link_libraries(ControlSystemAdapterOPCUA ${LIBXML2_LIBRARIES})

##########################################################################################################
## Custom Commands (z.b. model-compiler, autobuild-dependencies)
##########################################################################################################

add_custom_command(OUTPUT ${PROJECT_SOURCE_DIR}/tools/pyUANamespace/generate_open62541CCode.py
                           ${PROJECT_SOURCE_DIR}/tools/pyUANamespace/open62541_MacroHelper.py
                           ${PROJECT_SOURCE_DIR}/tools/pyUANamespace/ua_builtin_types.py
                           ${PROJECT_SOURCE_DIR}/tools/pyUANamespace/ua_constants.py
                           ${PROJECT_SOURCE_DIR}/tools/pyUANamespace/ua_namespace.py
                           ${PROJECT_SOURCE_DIR}/tools/pyUANamespace/ua_node_types.py
                           ${PROJECT_SOURCE_DIR}/lib/libopen62541.so
                           ${PROJECT_SOURCE_DIR}/include/open62541/open62541.h
                   PRE_BUILD
                   COMMAND /bin/bash ${PROJECT_SOURCE_DIR}/tools/buildDependencies.sh ${PROJECT_SOURCE_DIR}
                   DEPENDS ${PROJECT_SOURCE_DIR}/tools/buildDependencies.sh)

add_custom_command(OUTPUT ${PROJECT_BINARY_DIR}/src_generated/mtca_namespaceinit_generated.c
                          ${PROJECT_BINARY_DIR}/src_generated/mtca_namespaceinit_generated.h
                   PRE_BUILD
                   COMMAND ${PYTHON_EXECUTABLE} ${PROJECT_SOURCE_DIR}/tools/pyUANamespace/generate_open62541CCode.py
                                                -i ${PROJECT_SOURCE_DIR}/model/NodeID_Blacklist_FullNS0.txt
                                                -b ${PROJECT_SOURCE_DIR}/model/NodeID_Blacklist.txt
                                                ${PROJECT_SOURCE_DIR}/model/Opc.Ua.NodeSet2.xml
                                                ${PROJECT_SOURCE_DIR}/model/${MODEL_XML_FILE}
                                                ${PROJECT_BINARY_DIR}/src_generated/mtca_namespaceinit_generated
                   DEPENDS ${PROJECT_SOURCE_DIR}/model/Opc.Ua.NodeSet2.xml
                           ${PROJECT_SOURCE_DIR}/model/${MODEL_XML_FILE}
                           ${PROJECT_SOURCE_DIR}/model/NodeID_Blacklist_FullNS0.txt
                           ${PROJECT_SOURCE_DIR}/model/NodeID_Blacklist.txt
                           ${PROJECT_SOURCE_DIR}/tools/pyUANamespace/generate_open62541CCode.py
                           ${PROJECT_SOURCE_DIR}/tools/pyUANamespace/open62541_MacroHelper.py
                           ${PROJECT_SOURCE_DIR}/tools/pyUANamespace/ua_builtin_types.py
                           ${PROJECT_SOURCE_DIR}/tools/pyUANamespace/ua_constants.py
                           ${PROJECT_SOURCE_DIR}/tools/pyUANamespace/ua_namespace.py
                           ${PROJECT_SOURCE_DIR}/tools/pyUANamespace/ua_node_types.py)

                           
##########################################################################################################
##  Tests and executables
##########################################################################################################

link_directories(${CMAKE_BINARY_DIR})

add_executable(ControlSystem-OPCUA_Sample_Adapter ${CMAKE_SOURCE_DIR}/examples/ControlSystem_OPCUA_Sample_Adapter.cpp)
target_link_libraries(ControlSystem-OPCUA_Sample_Adapter ControlSystemAdapterOPCUA)
target_link_libraries(ControlSystem-OPCUA_Sample_Adapter open62541)
target_link_libraries(ControlSystem-OPCUA_Sample_Adapter pthread)
target_link_libraries(ControlSystem-OPCUA_Sample_Adapter
  ${Boost_FILESYSTEM_LIBRARY}
  ${Boost_SYSTEM_LIBRARY}
  ${Boost_THREAD_LIBRARY}
  ${Boost_CHRONO_LIBRARY}
)
target_link_libraries(ControlSystemAdapterOPCUA ${LIBXML2_LIBRARIES})

if(ENABLE_LINTING)
add_custom_command( TARGET ControlSystem-OPCUA_Sample_Adapter
                    PRE_BUILD
                    COMMAND /usr/bin/cppcheck --std=c++11 --inline-suppr --enable=all ${objectSources}
                    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
                    COMMENT "Running CppCheck on all CPP Sources" VERBATIM)
endif()
## Ends binary ControlSystem-OPCUA_Sample_Adapter


install(TARGETS ControlSystem-OPCUA_Sample_Adapter RUNTIME DESTINATION bin)
  
