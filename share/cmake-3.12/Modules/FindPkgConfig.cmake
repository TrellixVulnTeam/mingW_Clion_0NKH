# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file Copyright.txt or https://cmake.org/licensing for details.

#[========================================[.rst:
FindPkgConfig
-------------

A ``pkg-config`` module for CMake.

Finds the ``pkg-config`` executable and adds the :command:`pkg_get_variable`,
:command:`pkg_check_modules` and :command:`pkg_search_module` commands. The
following variables will also be set::

  PKG_CONFIG_FOUND          ... if pkg-config executable was found
  PKG_CONFIG_EXECUTABLE     ... pathname of the pkg-config program
  PKG_CONFIG_VERSION_STRING ... the version of the pkg-config program found
                                (since CMake 2.8.8)

#]========================================]

### Common stuff ####
set(PKG_CONFIG_VERSION 1)

# find pkg-config, use PKG_CONFIG if set
if((NOT PKG_CONFIG_EXECUTABLE) AND (NOT "$ENV{PKG_CONFIG}" STREQUAL ""))
  set(PKG_CONFIG_EXECUTABLE "$ENV{PKG_CONFIG}" CACHE FILEPATH "pkg-config executable")
endif()
find_program(PKG_CONFIG_EXECUTABLE NAMES pkg-config DOC "pkg-config executable")
mark_as_advanced(PKG_CONFIG_EXECUTABLE)

if (PKG_CONFIG_EXECUTABLE)
  execute_process(COMMAND ${PKG_CONFIG_EXECUTABLE} --version
    OUTPUT_VARIABLE PKG_CONFIG_VERSION_STRING
    ERROR_QUIET
    OUTPUT_STRIP_TRAILING_WHITESPACE)
endif ()

include(${CMAKE_CURRENT_LIST_DIR}/FindPackageHandleStandardArgs.cmake)
find_package_handle_standard_args(PkgConfig
                                  REQUIRED_VARS PKG_CONFIG_EXECUTABLE
                                  VERSION_VAR PKG_CONFIG_VERSION_STRING)

# This is needed because the module name is "PkgConfig" but the name of
# this variable has always been PKG_CONFIG_FOUND so this isn't automatically
# handled by FPHSA.
set(PKG_CONFIG_FOUND "${PKGCONFIG_FOUND}")

# Unsets the given variables
macro(_pkgconfig_unset var)
  set(${var} "" CACHE INTERNAL "")
endmacro()

macro(_pkgconfig_set var value)
  set(${var} ${value} CACHE INTERNAL "")
endmacro()

# Invokes pkgconfig, cleans up the result and sets variables
macro(_pkgconfig_invoke _pkglist _prefix _varname _regexp)
  set(_pkgconfig_invoke_result)

  if (PKG_CONFIG_WITHOUT_PREFIX)
    set(_pkgconfig_extra_arg "--dont-define-prefix")
  else()
    set(_pkgconfig_extra_arg "")
  endif()
  execute_process(
    COMMAND ${PKG_CONFIG_EXECUTABLE} ${_pkgconfig_extra_arg} ${ARGN} ${_pkglist}
    OUTPUT_VARIABLE _pkgconfig_invoke_result
    RESULT_VARIABLE _pkgconfig_failed
    OUTPUT_STRIP_TRAILING_WHITESPACE)

  if (_pkgconfig_failed)
    set(_pkgconfig_${_varname} "")
    _pkgconfig_unset(${_prefix}_${_varname})
  else()
    string(REGEX REPLACE "[\r\n]"       " " _pkgconfig_invoke_result "${_pkgconfig_invoke_result}")

    if (NOT ${_regexp} STREQUAL "")
      string(REGEX REPLACE "${_regexp}" " " _pkgconfig_invoke_result "${_pkgconfig_invoke_result}")
    endif()

    separate_arguments(_pkgconfig_invoke_result)

    #message(STATUS "  ${_varname} ... ${_pkgconfig_invoke_result}")
    set(_pkgconfig_${_varname} ${_pkgconfig_invoke_result})
    _pkgconfig_set(${_prefix}_${_varname} "${_pkgconfig_invoke_result}")
  endif()
endmacro()

#[========================================[.rst:
.. command:: pkg_get_variable

  Retrieves the value of a pkg-config variable ``varName`` and stores it in the
  result variable ``resultVar`` in the calling scope. ::

    pkg_get_variable(<resultVar> <moduleName> <varName>)

  If ``pkg-config`` returns multiple values for the specified variable,
  ``resultVar`` will contain a :ref:`;-list <CMake Language Lists>`.

  For example:

  .. code-block:: cmake

    pkg_get_variable(GI_GIRDIR gobject-introspection-1.0 girdir)
#]========================================]
function (pkg_get_variable result pkg variable)
  _pkgconfig_invoke("${pkg}" "prefix" "result" "" "--variable=${variable}")
  set("${result}"
    "${prefix_result}"
    PARENT_SCOPE)
endfunction ()

# Invokes pkgconfig two times; once without '--static' and once with
# '--static'
macro(_pkgconfig_invoke_dyn _pkglist _prefix _varname cleanup_regexp)
  _pkgconfig_invoke("${_pkglist}" ${_prefix}        ${_varname} "${cleanup_regexp}" ${ARGN})
  _pkgconfig_invoke("${_pkglist}" ${_prefix} STATIC_${_varname} "${cleanup_regexp}" --static  ${ARGN})
endmacro()

# Splits given arguments into options and a package list
macro(_pkgconfig_parse_options _result _is_req _is_silent _no_cmake_path _no_cmake_environment_path _imp_target)
  set(${_is_req} 0)
  set(${_is_silent} 0)
  set(${_no_cmake_path} 0)
  set(${_no_cmake_environment_path} 0)
  set(${_imp_target} 0)
  if(DEFINED PKG_CONFIG_USE_CMAKE_PREFIX_PATH)
    if(NOT PKG_CONFIG_USE_CMAKE_PREFIX_PATH)
      set(${_no_cmake_path} 1)
      set(${_no_cmake_environment_path} 1)
    endif()
  elseif(CMAKE_MINIMUM_REQUIRED_VERSION VERSION_LESS 3.1)
    set(${_no_cmake_path} 1)
    set(${_no_cmake_environment_path} 1)
  endif()

  foreach(_pkg ${ARGN})
    if (_pkg STREQUAL "REQUIRED")
      set(${_is_req} 1)
    endif ()
    if (_pkg STREQUAL "QUIET")
      set(${_is_silent} 1)
    endif ()
    if (_pkg STREQUAL "NO_CMAKE_PATH")
      set(${_no_cmake_path} 1)
    endif()
    if (_pkg STREQUAL "NO_CMAKE_ENVIRONMENT_PATH")
      set(${_no_cmake_environment_path} 1)
    endif()
    if (_pkg STREQUAL "IMPORTED_TARGET")
      set(${_imp_target} 1)
    endif()
  endforeach()

  set(${_result} ${ARGN})
  list(REMOVE_ITEM ${_result} "REQUIRED")
  list(REMOVE_ITEM ${_result} "QUIET")
  list(REMOVE_ITEM ${_result} "NO_CMAKE_PATH")
  list(REMOVE_ITEM ${_result} "NO_CMAKE_ENVIRONMENT_PATH")
  list(REMOVE_ITEM ${_result} "IMPORTED_TARGET")
endmacro()

# Add the content of a variable or an environment variable to a list of
# paths
# Usage:
#  - _pkgconfig_add_extra_path(_extra_paths VAR)
#  - _pkgconfig_add_extra_path(_extra_paths ENV VAR)
function(_pkgconfig_add_extra_path _extra_paths_var _var)
  set(_is_env 0)
  if(ARGC GREATER 2 AND _var STREQUAL "ENV")
    set(_var ${ARGV2})
    set(_is_env 1)
  endif()
  if(NOT _is_env)
    if(NOT "${${_var}}" STREQUAL "")
      list(APPEND ${_extra_paths_var} ${${_var}})
    endif()
  else()
    if(NOT "$ENV{${_var}}" STREQUAL "")
      file(TO_CMAKE_PATH "$ENV{${_var}}" _path)
      list(APPEND ${_extra_paths_var} ${_path})
      unset(_path)
    endif()
  endif()
  set(${_extra_paths_var} ${${_extra_paths_var}} PARENT_SCOPE)
endfunction()

# scan the LDFLAGS returned by pkg-config for library directories and
# libraries, figure out the absolute paths of that libraries in the
# given directories
function(_pkg_find_libs _prefix _no_cmake_path _no_cmake_environment_path)
  unset(_libs)
  unset(_find_opts)

  # set the options that are used as long as the .pc file does not provide a library
  # path to look into
  if(_no_cmake_path)
    list(APPEND _find_opts "NO_CMAKE_PATH")
  endif()
  if(_no_cmake_environment_path)
    list(APPEND _find_opts "NO_CMAKE_ENVIRONMENT_PATH")
  endif()

  unset(_search_paths)
  foreach (flag IN LISTS ${_prefix}_LDFLAGS)
    if (flag MATCHES "^-L(.*)")
      list(APPEND _search_paths ${CMAKE_MATCH_1})
      continue()
    endif()
    if (flag MATCHES "^-l(.*)")
      set(_pkg_search "${CMAKE_MATCH_1}")
    else()
      continue()
    endif()

    if(_search_paths)
        # Firstly search in -L paths
        find_library(pkgcfg_lib_${_prefix}_${_pkg_search}
                     NAMES ${_pkg_search}
                     HINTS ${_search_paths} NO_DEFAULT_PATH)
    endif()
    find_library(pkgcfg_lib_${_prefix}_${_pkg_search}
                 NAMES ${_pkg_search}
                 ${_find_opts})
    list(APPEND _libs "${pkgcfg_lib_${_prefix}_${_pkg_search}}")
  endforeach()

  set(${_prefix}_LINK_LIBRARIES "${_libs}" PARENT_SCOPE)
endfunction()

# create an imported target from all the information returned by pkg-config
function(_pkg_create_imp_target _prefix)
  # only create the target if it is linkable, i.e. no executables
  if (NOT TARGET PkgConfig::${_prefix}
      AND ( ${_prefix}_INCLUDE_DIRS OR ${_prefix}_LINK_LIBRARIES OR ${_prefix}_CFLAGS_OTHER ))
    add_library(PkgConfig::${_prefix} INTERFACE IMPORTED)

    if(${_prefix}_INCLUDE_DIRS)
      set_property(TARGET PkgConfig::${_prefix} PROPERTY
                   INTERFACE_INCLUDE_DIRECTORIES "${${_prefix}_INCLUDE_DIRS}")
    endif()
    if(${_prefix}_LINK_LIBRARIES)
      set_property(TARGET PkgConfig::${_prefix} PROPERTY
                   INTERFACE_LINK_LIBRARIES "${${_prefix}_LINK_LIBRARIES}")
    endif()
    if(${_prefix}_CFLAGS_OTHER)
      set_property(TARGET PkgConfig::${_prefix} PROPERTY
                   INTERFACE_COMPILE_OPTIONS "${${_prefix}_CFLAGS_OTHER}")
    endif()
  endif()
endfunction()

# recalculate the dynamic output
# this is a macro and not a function so the result of _pkg_find_libs is automatically propagated
macro(_pkg_recalculate _prefix _no_cmake_path _no_cmake_environment_path _imp_target)
  _pkg_find_libs(${_prefix} ${_no_cmake_path} ${_no_cmake_environment_path})
  if(${_imp_target})
    _pkg_create_imp_target(${_prefix})
  endif()
endmacro()

###
macro(_pkg_check_modules_internal _is_required _is_silent _no_cmake_path _no_cmake_environment_path _imp_target _prefix)
  _pkgconfig_unset(${_prefix}_FOUND)
  _pkgconfig_unset(${_prefix}_VERSION)
  _pkgconfig_unset(${_prefix}_PREFIX)
  _pkgconfig_unset(${_prefix}_INCLUDEDIR)
  _pkgconfig_unset(${_prefix}_LIBDIR)
  _pkgconfig_unset(${_prefix}_LIBS)
  _pkgconfig_unset(${_prefix}_LIBS_L)
  _pkgconfig_unset(${_prefix}_LIBS_PATHS)
  _pkgconfig_unset(${_prefix}_LIBS_OTHER)
  _pkgconfig_unset(${_prefix}_CFLAGS)
  _pkgconfig_unset(${_prefix}_CFLAGS_I)
  _pkgconfig_unset(${_prefix}_CFLAGS_OTHER)
  _pkgconfig_unset(${_prefix}_STATIC_LIBDIR)
  _pkgconfig_unset(${_prefix}_STATIC_LIBS)
  _pkgconfig_unset(${_prefix}_STATIC_LIBS_L)
  _pkgconfig_unset(${_prefix}_STATIC_LIBS_PATHS)
  _pkgconfig_unset(${_prefix}_STATIC_LIBS_OTHER)
  _pkgconfig_unset(${_prefix}_STATIC_CFLAGS)
  _pkgconfig_unset(${_prefix}_STATIC_CFLAGS_I)
  _pkgconfig_unset(${_prefix}_STATIC_CFLAGS_OTHER)

  # create a better addressable variable of the modules and calculate its size
  set(_pkg_check_modules_list ${ARGN})
  list(LENGTH _pkg_check_modules_list _pkg_check_modules_cnt)

  if(PKG_CONFIG_EXECUTABLE)
    # give out status message telling checked module
    if (NOT ${_is_silent})
      if (_pkg_check_modules_cnt EQUAL 1)
        message(STATUS "Checking for module '${_pkg_check_modules_list}'")
      else()
        message(STATUS "Checking for modules '${_pkg_check_modules_list}'")
      endif()
    endif()

    set(_pkg_check_modules_packages)
    set(_pkg_check_modules_failed)

    set(_extra_paths)

    if(NOT _no_cmake_path)
      _pkgconfig_add_extra_path(_extra_paths CMAKE_PREFIX_PATH)
      _pkgconfig_add_extra_path(_extra_paths CMAKE_FRAMEWORK_PATH)
      _pkgconfig_add_extra_path(_extra_paths CMAKE_APPBUNDLE_PATH)
    endif()

    if(NOT _no_cmake_environment_path)
      _pkgconfig_add_extra_path(_extra_paths ENV CMAKE_PREFIX_PATH)
      _pkgconfig_add_extra_path(_extra_paths ENV CMAKE_FRAMEWORK_PATH)
      _pkgconfig_add_extra_path(_extra_paths ENV CMAKE_APPBUNDLE_PATH)
    endif()

    if(NOT "${_extra_paths}" STREQUAL "")
      # Save the PKG_CONFIG_PATH environment variable, and add paths
      # from the CMAKE_PREFIX_PATH variables
      set(_pkgconfig_path_old "$ENV{PKG_CONFIG_PATH}")
      set(_pkgconfig_path "${_pkgconfig_path_old}")
      if(NOT "${_pkgconfig_path}" STREQUAL "")
        file(TO_CMAKE_PATH "${_pkgconfig_path}" _pkgconfig_path)
      endif()

      # Create a list of the possible pkgconfig subfolder (depending on
      # the system
      set(_lib_dirs)
      if(NOT DEFINED CMAKE_SYSTEM_NAME
          OR (CMAKE_SYSTEM_NAME MATCHES "^(Linux|kFreeBSD|GNU)$"
              AND NOT CMAKE_CROSSCOMPILING))
        if(EXISTS "/etc/debian_version") # is this a debian system ?
          if(CMAKE_LIBRARY_ARCHITECTURE)
            list(APPEND _lib_dirs "lib/${CMAKE_LIBRARY_ARCHITECTURE}/pkgconfig")
          endif()
        else()
          # not debian, check the FIND_LIBRARY_USE_LIB32_PATHS and FIND_LIBRARY_USE_LIB64_PATHS properties
          get_property(uselib32 GLOBAL PROPERTY FIND_LIBRARY_USE_LIB32_PATHS)
          if(uselib32 AND CMAKE_SIZEOF_VOID_P EQUAL 4)
            list(APPEND _lib_dirs "lib32/pkgconfig")
          endif()
          get_property(uselib64 GLOBAL PROPERTY FIND_LIBRARY_USE_LIB64_PATHS)
          if(uselib64 AND CMAKE_SIZEOF_VOID_P EQUAL 8)
            list(APPEND _lib_dirs "lib64/pkgconfig")
          endif()
          get_property(uselibx32 GLOBAL PROPERTY FIND_LIBRARY_USE_LIBX32_PATHS)
          if(uselibx32 AND CMAKE_INTERNAL_PLATFORM_ABI STREQUAL "ELF X32")
            list(APPEND _lib_dirs "libx32/pkgconfig")
          endif()
        endif()
      endif()
      if(CMAKE_SYSTEM_NAME STREQUAL "FreeBSD" AND NOT CMAKE_CROSSCOMPILING)
        list(APPEND _lib_dirs "libdata/pkgconfig")
      endif()
      list(APPEND _lib_dirs "lib/pkgconfig")
      list(APPEND _lib_dirs "share/pkgconfig")

      # Check if directories exist and eventually append them to the
      # pkgconfig path list
      foreach(_prefix_dir ${_extra_paths})
        foreach(_lib_dir ${_lib_dirs})
          if(EXISTS "${_prefix_dir}/${_lib_dir}")
            list(APPEND _pkgconfig_path "${_prefix_dir}/${_lib_dir}")
            list(REMOVE_DUPLICATES _pkgconfig_path)
          endif()
        endforeach()
      endforeach()

      # Prepare and set the environment variable
      if(NOT "${_pkgconfig_path}" STREQUAL "")
        # remove empty values from the list
        list(REMOVE_ITEM _pkgconfig_path "")
        file(TO_NATIVE_PATH "${_pkgconfig_path}" _pkgconfig_path)
        if(UNIX)
          string(REPLACE ";" ":" _pkgconfig_path "${_pkgconfig_path}")
          string(REPLACE "\\ " " " _pkgconfig_path "${_pkgconfig_path}")
        endif()
        set(ENV{PKG_CONFIG_PATH} "${_pkgconfig_path}")
      endif()

      # Unset variables
      unset(_lib_dirs)
      unset(_pkgconfig_path)
    endif()

    # iterate through module list and check whether they exist and match the required version
    foreach (_pkg_check_modules_pkg ${_pkg_check_modules_list})
      set(_pkg_check_modules_exist_query)

      # check whether version is given
      if (_pkg_check_modules_pkg MATCHES "(.*[^><])(>=|=|<=)(.*)")
        set(_pkg_check_modules_pkg_name "${CMAKE_MATCH_1}")
        set(_pkg_check_modules_pkg_op "${CMAKE_MATCH_2}")
        set(_pkg_check_modules_pkg_ver "${CMAKE_MATCH_3}")
      else()
        set(_pkg_check_modules_pkg_name "${_pkg_check_modules_pkg}")
        set(_pkg_check_modules_pkg_op)
        set(_pkg_check_modules_pkg_ver)
      endif()

      _pkgconfig_unset(${_prefix}_${_pkg_check_modules_pkg_name}_VERSION)
      _pkgconfig_unset(${_prefix}_${_pkg_check_modules_pkg_name}_PREFIX)
      _pkgconfig_unset(${_prefix}_${_pkg_check_modules_pkg_name}_INCLUDEDIR)
      _pkgconfig_unset(${_prefix}_${_pkg_check_modules_pkg_name}_LIBDIR)

      list(APPEND _pkg_check_modules_packages    "${_pkg_check_modules_pkg_name}")

      # create the final query which is of the format:
      # * <pkg-name> >= <version>
      # * <pkg-name> = <version>
      # * <pkg-name> <= <version>
      # * --exists <pkg-name>
      list(APPEND _pkg_check_modules_exist_query --print-errors --short-errors)
      if (_pkg_check_modules_pkg_op)
        list(APPEND _pkg_check_modules_exist_query "${_pkg_check_modules_pkg_name} ${_pkg_check_modules_pkg_op} ${_pkg_check_modules_pkg_ver}")
      else()
        list(APPEND _pkg_check_modules_exist_query --exists)
        list(APPEND _pkg_check_modules_exist_query "${_pkg_check_modules_pkg_name}")
      endif()

      # execute the query
      execute_process(
        COMMAND ${PKG_CONFIG_EXECUTABLE} ${_pkg_check_modules_exist_query}
        RESULT_VARIABLE _pkgconfig_retval
        ERROR_VARIABLE _pkgconfig_error
        ERROR_STRIP_TRAILING_WHITESPACE)

      # evaluate result and tell failures
      if (_pkgconfig_retval)
        if(NOT ${_is_silent})
          message(STATUS "  ${_pkgconfig_error}")
        endif()

        set(_pkg_check_modules_failed 1)
      endif()
    endforeach()

    if(_pkg_check_modules_failed)
      # fail when requested
      if (${_is_required})
        message(FATAL_ERROR "A required package was not found")
      endif ()
    else()
      # when we are here, we checked whether requested modules
      # exist. Now, go through them and set variables

      _pkgconfig_set(${_prefix}_FOUND 1)
      list(LENGTH _pkg_check_modules_packages pkg_count)

      # iterate through all modules again and set individual variables
      foreach (_pkg_check_modules_pkg ${_pkg_check_modules_packages})
        # handle case when there is only one package required
        if (pkg_count EQUAL 1)
          set(_pkg_check_prefix "${_prefix}")
        else()
          set(_pkg_check_prefix "${_prefix}_${_pkg_check_modules_pkg}")
        endif()

        _pkgconfig_invoke(${_pkg_check_modules_pkg} "${_pkg_check_prefix}" VERSION    ""   --modversion )
        pkg_get_variable("${_pkg_check_prefix}_PREFIX" ${_pkg_check_modules_pkg} "prefix")
        pkg_get_variable("${_pkg_check_prefix}_INCLUDEDIR" ${_pkg_check_modules_pkg} "includedir")
        pkg_get_variable("${_pkg_check_prefix}_LIBDIR" ${_pkg_check_modules_pkg} "libdir")
        foreach (variable IN ITEMS PREFIX INCLUDEDIR LIBDIR)
          _pkgconfig_set("${_pkg_check_prefix}_${variable}" "${${_pkg_check_prefix}_${variable}}")
        endforeach ()

        if (NOT ${_is_silent})
          message(STATUS "  Found ${_pkg_check_modules_pkg}, version ${_pkgconfig_VERSION}")
        endif ()
      endforeach()

      # set variables which are combined for multiple modules
      _pkgconfig_invoke_dyn("${_pkg_check_modules_packages}" "${_prefix}" LIBRARIES           "(^| )-l" --libs-only-l )
      _pkgconfig_invoke_dyn("${_pkg_check_modules_packages}" "${_prefix}" LIBRARY_DIRS        "(^| )-L" --libs-only-L )
      _pkgconfig_invoke_dyn("${_pkg_check_modules_packages}" "${_prefix}" LDFLAGS             ""        --libs )
      _pkgconfig_invoke_dyn("${_pkg_check_modules_packages}" "${_prefix}" LDFLAGS_OTHER       ""        --libs-only-other )

      _pkgconfig_invoke_dyn("${_pkg_check_modules_packages}" "${_prefix}" INCLUDE_DIRS        "(^| )-I" --cflags-only-I )
      _pkgconfig_invoke_dyn("${_pkg_check_modules_packages}" "${_prefix}" CFLAGS              ""        --cflags )
      _pkgconfig_invoke_dyn("${_pkg_check_modules_packages}" "${_prefix}" CFLAGS_OTHER        ""        --cflags-only-other )

      _pkg_recalculate("${_prefix}" ${_no_cmake_path} ${_no_cmake_environment_path} ${_imp_target})
    endif()

    if(NOT "${_extra_paths}" STREQUAL "")
      # Restore the environment variable
      set(ENV{PKG_CONFIG_PATH} "${_pkgconfig_path_old}")
    endif()

    unset(_extra_paths)
    unset(_pkgconfig_path_old)
  else()
    if (${_is_required})
      message(SEND_ERROR "pkg-config tool not found")
    endif ()
  endif()
endmacro()


#[========================================[.rst:
.. command:: pkg_check_modules

  Checks for all the given modules, setting a variety of result variables in
  the calling scope. ::

    pkg_check_modules(<prefix>
                      [REQUIRED] [QUIET]
                      [NO_CMAKE_PATH]
                      [NO_CMAKE_ENVIRONMENT_PATH]
                      [IMPORTED_TARGET]
                      <moduleSpec> [<moduleSpec>...])

  When the ``REQUIRED`` argument is given, the command will fail with an error
  if module(s) could not be found.

  When the ``QUIET`` argument is given, no status messages will be printed.

  By default, if :variable:`CMAKE_MINIMUM_REQUIRED_VERSION` is 3.1 or
  later, or if :variable:`PKG_CONFIG_USE_CMAKE_PREFIX_PATH` is set to a
  boolean ``True`` value, then the :variable:`CMAKE_PREFIX_PATH`,
  :variable:`CMAKE_FRAMEWORK_PATH`, and :variable:`CMAKE_APPBUNDLE_PATH` cache
  and environment variables will be added to the ``pkg-config`` search path.
  The ``NO_CMAKE_PATH`` and ``NO_CMAKE_ENVIRONMENT_PATH`` arguments
  disable this behavior for the cache variables and environment variables
  respectively.

  The ``IMPORTED_TARGET`` argument will create an imported target named
  ``PkgConfig::<prefix>`` that can be passed directly as an argument to
  :command:`target_link_libraries`.

  Each ``<moduleSpec>`` must be in one of the following formats::

    {moduleName}            ... matches any version
    {moduleName}>={version} ... at least version <version> is required
    {moduleName}={version}  ... exactly version <version> is required
    {moduleName}<={version} ... modules must not be newer than <version>

  The following variables may be set upon return.  Two sets of values exist,
  one for the common case (``<XXX> = <prefix>``) and another for the
  information ``pkg-config`` provides when it is called with the ``--static``
  option (``<XXX> = <prefix>_STATIC``)::

    <XXX>_FOUND          ... set to 1 if module(s) exist
    <XXX>_LIBRARIES      ... only the libraries (without the '-l')
    <XXX>_LINK_LIBRARIES ... the libraries and their absolute paths
    <XXX>_LIBRARY_DIRS   ... the paths of the libraries (without the '-L')
    <XXX>_LDFLAGS        ... all required linker flags
    <XXX>_LDFLAGS_OTHER  ... all other linker flags
    <XXX>_INCLUDE_DIRS   ... the '-I' preprocessor flags (without the '-I')
    <XXX>_CFLAGS         ... all required cflags
    <XXX>_CFLAGS_OTHER   ... the other compiler flags

  All but ``<XXX>_FOUND`` may be a :ref:`;-list <CMake Language Lists>` if the
  associated variable returned from ``pkg-config`` has multiple values.

  There are some special variables whose prefix depends on the number of
  ``<moduleSpec>`` given.  When there is only one ``<moduleSpec>``,
  ``<YYY>`` will simply be ``<prefix>``, but if two or more ``<moduleSpec>``
  items are given, ``<YYY>`` will be ``<prefix>_<moduleName>``::

    <YYY>_VERSION    ... version of the module
    <YYY>_PREFIX     ... prefix directory of the module
    <YYY>_INCLUDEDIR ... include directory of the module
    <YYY>_LIBDIR     ... lib directory of the module

  Examples

  .. code-block:: cmake

    pkg_check_modules (GLIB2 glib-2.0)

  Looks for any version of glib2.  If found, the output variable
  ``GLIB2_VERSION`` will hold the actual version found.

  .. code-block:: cmake

    pkg_check_modules (GLIB2 glib-2.0>=2.10)

  Looks for at least version 2.10 of glib2.  If found, the output variable
  ``GLIB2_VERSION`` will hold the actual version found.

  .. code-block:: cmake

    pkg_check_modules (FOO glib-2.0>=2.10 gtk+-2.0)

  Looks for both glib2-2.0 (at least version 2.10) and any version of
  gtk2+-2.0.  Only if both are found will ``FOO`` be considered found.
  The ``FOO_glib-2.0_VERSION`` and ``FOO_gtk+-2.0_VERSION`` variables will be
  set to their respective found module versions.

  .. code-block:: cmake

    pkg_check_modules (XRENDER REQUIRED xrender)

  Requires any version of ``xrender``.  Example output variables set by a
  successful call::

    XRENDER_LIBRARIES=Xrender;X11
    XRENDER_STATIC_LIBRARIES=Xrender;X11;pthread;Xau;Xdmcp
#]========================================]
macro(pkg_check_modules _prefix _module0)
  _pkgconfig_parse_options(_pkg_modules _pkg_is_required _pkg_is_silent _no_cmake_path _no_cmake_environment_path _imp_target "${_module0}" ${ARGN})
  # check cached value
  if (NOT DEFINED __pkg_config_checked_${_prefix} OR __pkg_config_checked_${_prefix} LESS ${PKG_CONFIG_VERSION} OR NOT ${_prefix}_FOUND OR
      (NOT "${ARGN}" STREQUAL "" AND NOT "${__pkg_config_arguments_${_prefix}}" STREQUAL "${_module0};${ARGN}") OR
      (    "${ARGN}" STREQUAL "" AND NOT "${__pkg_config_arguments_${_prefix}}" STREQUAL "${_module0}"))
    _pkg_check_modules_internal("${_pkg_is_required}" "${_pkg_is_silent}" ${_no_cmake_path} ${_no_cmake_environment_path} ${_imp_target} "${_prefix}" ${_pkg_modules})

    _pkgconfig_set(__pkg_config_checked_${_prefix} ${PKG_CONFIG_VERSION})
    if (${_prefix}_FOUND)
      _pkgconfig_set(__pkg_config_arguments_${_prefix} "${_module0};${ARGN}")
    endif()
  else()
    if (${_prefix}_FOUND)
      _pkg_recalculate("${_prefix}" ${_no_cmake_path} ${_no_cmake_environment_path} ${_imp_target})
    endif()
  endif()
endmacro()


#[========================================[.rst:
.. command:: pkg_search_module

  The behavior of this command is the same as :command:`pkg_check_modules`,
  except that rather than checking for all the specified modules, it searches
  for just the first successful match. ::

    pkg_search_module(<prefix>
                      [REQUIRED] [QUIET]
                      [NO_CMAKE_PATH]
                      [NO_CMAKE_ENVIRONMENT_PATH]
                      [IMPORTED_TARGET]
                      <moduleSpec> [<moduleSpec>...])

  Examples

  .. code-block:: cmake

    pkg_search_module (BAR libxml-2.0 libxml2 libxml>=2)
#]========================================]
macro(pkg_search_module _prefix _module0)
  _pkgconfig_parse_options(_pkg_modules_alt _pkg_is_required _pkg_is_silent _no_cmake_path _no_cmake_environment_path _imp_target "${_module0}" ${ARGN})
  # check cached value
  if (NOT DEFINED __pkg_config_checked_${_prefix} OR __pkg_config_checked_${_prefix} LESS ${PKG_CONFIG_VERSION} OR NOT ${_prefix}_FOUND)
    set(_pkg_modules_found 0)

    if (NOT ${_pkg_is_silent})
      message(STATUS "Checking for one of the modules '${_pkg_modules_alt}'")
    endif ()

    # iterate through all modules and stop at the first working one.
    foreach(_pkg_alt ${_pkg_modules_alt})
      if(NOT _pkg_modules_found)
        _pkg_check_modules_internal(0 1 ${_no_cmake_path} ${_no_cmake_environment_path} ${_imp_target} "${_prefix}" "${_pkg_alt}")
      endif()

      if (${_prefix}_FOUND)
        set(_pkg_modules_found 1)
      endif()
    endforeach()

    if (NOT ${_prefix}_FOUND)
      if(${_pkg_is_required})
        message(SEND_ERROR "None of the required '${_pkg_modules_alt}' found")
      endif()
    endif()

    _pkgconfig_set(__pkg_config_checked_${_prefix} ${PKG_CONFIG_VERSION})
  elseif (${_prefix}_FOUND)
    _pkg_recalculate("${_prefix}" ${_no_cmake_path} ${_no_cmake_environment_path} ${_imp_target})
  endif()
endmacro()


#[========================================[.rst:
Variables Affecting Behavior
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. variable:: PKG_CONFIG_EXECUTABLE

  This can be set to the path of the pkg-config executable.  If not provided,
  it will be set by the module as a result of calling :command:`find_program`
  internally.  The ``PKG_CONFIG`` environment variable can be used as a hint.

.. variable:: PKG_CONFIG_USE_CMAKE_PREFIX_PATH

  Specifies whether :command:`pkg_check_modules` and
  :command:`pkg_search_module` should add the paths in the
  :variable:`CMAKE_PREFIX_PATH`, :variable:`CMAKE_FRAMEWORK_PATH` and
  :variable:`CMAKE_APPBUNDLE_PATH` cache and environment variables to the
  ``pkg-config`` search path.

  If this variable is not set, this behavior is enabled by default if
  :variable:`CMAKE_MINIMUM_REQUIRED_VERSION` is 3.1 or later, disabled
  otherwise.
#]========================================]


### Local Variables:
### mode: cmake
### End:
