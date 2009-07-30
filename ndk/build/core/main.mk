# Copyright (C) 2009 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# ====================================================================
#
# Define the main configuration variables, and read the host-specific
# configuration file that is normally generated by build/host-setup.sh
#
# ====================================================================

# The location of the build system files
BUILD_SYSTEM := $(strip $(dir $(lastword $(MAKEFILE_LIST))))
BUILD_SYSTEM := $(BUILD_SYSTEM:%/=%)

# Include common definitions
include build/core/definitions.mk

# Where all generated files will be stored during a build
NDK_OUT := out

# Read the host-specific configuration file in $(NDK_OUT)
#
HOST_CONFIG_MAKE := $(NDK_OUT)/host/config.mk

ifeq ($(strip $(wildcard $(HOST_CONFIG_MAKE))),)
    $(call __ndk_info,\
    The configuration file '$(HOST_CONFIG_MAKE)' doesnt' exist.)
    $(call __ndk_info,\
       Please run 'build/host-setup.sh' to generate it.)
    $(call __ndk_error, Aborting)
endif

include $(HOST_CONFIG_MAKE)
HOST_PREBUILT_TAG := $(HOST_TAG)

# Location where all prebuilt binaries for a given host architectures
# will be stored.
HOST_PREBUILT := build/prebuilt/$(HOST_TAG)

# Where all app-specific generated files will be stored
NDK_APP_OUT := $(NDK_OUT)/apps

# Where all host-specific generated files will be stored
NDK_HOST_OUT := $(NDK_OUT)/host/$(HOST_TAG)

# ====================================================================
#
# Read all toolchain-specific configuration files.
#
# Each toolchain must have a corresponding config.mk file located
# in build/toolchains/<name>/ that will be included here.
#
# Each one of these files should define the following variables:
#   TOOLCHAIN_NAME   toolchain name (e.g. arm-eabi-4.2.1)
#   TOOLCHAIN_ABIS   list of target ABIs supported by the toolchain.
#
# Then, it should include $(ADD_TOOLCHAIN) which will perform
# book-keeping for the build system.
#
# ====================================================================

# the build script to include in each toolchain config.mk
ADD_TOOLCHAIN := $(BUILD_SYSTEM)/add-toolchain.mk

# the list of all toolchains in this NDK
NDK_ALL_TOOLCHAINS :=
NDK_ALL_ABIS       :=

TOOLCHAIN_CONFIGS := $(wildcard build/toolchains/*/config.mk)
$(foreach _config_mk,$(TOOLCHAIN_CONFIGS),\
  $(eval include $(BUILD_SYSTEM)/add-toolchain.mk)\
)

#$(info ALL_TOOLCHAINS=$(ALL_TOOLCHAINS))
NDK_TARGET_TOOLCHAIN := $(firstword $(NDK_ALL_TOOLCHAINS))
$(call ndk_log, Default toolchain is $(NDK_TARGET_TOOLCHAIN))

NDK_ALL_TOOLCHAINS   := $(call uniq,$(NDK_ALL_TOOLCHAINS))
NDK_ALL_ABIS         := $(call uniq,$(NDK_ALL_ABIS))

$(call ndk_log, This NDK supports the following toolchains and target ABIs:)
$(foreach tc,$(NDK_ALL_TOOLCHAINS),\
    $(call ndk_log, $(space)$(space)$(tc):  $(NDK_TOOLCHAIN.$(tc).abis))\
)

# ====================================================================
#
# Read all platform-specific configuration files.
#
# Each platform must be located in build/platforms/android-<apilevel>
# where <apilevel> corresponds to an API level number, with:
#   3 -> Android 1.5
#   4 -> next platform release
#
# ====================================================================

NDK_PLATFORMS_ROOT := $(BUILD_SYSTEM)/../platforms
NDK_ALL_PLATFORMS := $(strip $(notdir $(wildcard $(NDK_PLATFORMS_ROOT)/android-*)))
$(info NDK_ALL_PLATFORMS=$(NDK_ALL_PLATFORMS))

$(foreach _platform,$(NDK_ALL_PLATFORMS),\
  $(eval include $(BUILD_SYSTEM)/add-platform.mk)\
)

# ====================================================================
#
# Read all application configuration files
#
# Each 'application' must have a corresponding Application.mk file
# located in apps/<name> where <name> is a liberal name that doesn't
# contain any space in it, used to uniquely identify the
#
# See docs/ANDROID-MK.TXT for their specification.
#
# ====================================================================

NDK_ALL_APPS :=

NDK_APPLICATIONS := $(wildcard apps/*/Application.mk)
$(foreach _application_mk, $(NDK_APPLICATIONS),\
  $(eval include $(BUILD_SYSTEM)/add-application.mk)\
)

# clean up environment, just to be safe
$(call clear-vars, $(NDK_APP_VARS))

ifeq ($(strip $(NDK_ALL_APPS)),)
  $(call __ndk_info,\
    The NDK could not find a proper application description under apps/*/Application.mk)
  $(call __ndk_info,\
    Please follow the instructions in docs/NDK-APPS.TXT to write one.)
  $(call __ndk_error, Aborting)
endif

ifeq ($(strip $(APP)),)
  $(call __ndk_info,\
    The APP variable is undefined or empty.)
  $(call __ndk_info,\
    Please define it to one of: $(NDK_ALL_APPS))
  $(call __ndk_info,\
    You can also add new applications by writing an Application.mk file.)
  $(call __ndk_info,\
    See docs/APPLICATION-MK.TXT for details.)
  $(call __ndk_error, Aborting)
endif

# now check that APP doesn't contain an unknown app name
# if it does, we ignore them if there is at least one known
# app name in the list. Otherwise, abort with an error message
#
_unknown_apps := $(filter-out $(NDK_ALL_APPS),$(APP))
_known_apps   := $(filter     $(NDK_ALL_APPS),$(APP))

NDK_APPS := $(APP)

$(if $(_unknown_apps),\
  $(if $(_known_apps),\
    $(call __ndk_info,WARNING:\
        Removing unknown names from APP variable: $(_unknown_apps))\
    $(eval NDK_APPS := $(_known_apps))\
   ,\
    $(call __ndk_info,\
        The APP variable contains unknown app names: $(_unknown_apps))\
    $(call __ndk_info,\
        Please use one of: $(NDK_ALL_APPS))\
    $(call __ndk_error, Aborting)\
  )\
)

$(call __ndk_info,Building for application '$(NDK_APPS)')

# ====================================================================
#
# Prepare the build for parsing Android.mk files
#
# ====================================================================

# These phony targets are used to control various stages of the build
.PHONY: all \
        host_libraries host_executables \
        installed_modules \
        executables libraries static_libraries shared_libraries \
        clean clean-config clean-objs-dir \
        clean-executables clean-libraries \
        clean-installed-modules

# These macros are used in Android.mk to include the corresponding
# build script that will parse the LOCAL_XXX variable definitions.
#
CLEAR_VARS                := $(BUILD_SYSTEM)/clear-vars.mk
BUILD_HOST_EXECUTABLE     := $(BUILD_SYSTEM)/build-host-executable.mk
BUILD_HOST_STATIC_LIBRARY := $(BUILD_SYSTEM)/build-host-static-library.mk
BUILD_STATIC_LIBRARY      := $(BUILD_SYSTEM)/build-static-library.mk
BUILD_SHARED_LIBRARY      := $(BUILD_SYSTEM)/build-shared-library.mk
BUILD_EXECUTABLE          := $(BUILD_SYSTEM)/build-executable.mk

ANDROID_MK_INCLUDED := \
  $(CLEAR_VARS) \
  $(BUILD_HOST_EXECUTABLE) \
  $(BUILD_HOST_STATIC_LIBRARY) \
  $(BUILD_STATIC_LIBRARY) \
  $(BUILD_SHARED_LIBRARY) \
  $(BUILD_EXECUTABLE) \


# this is the list of directories containing dependency information
# generated during the build. It will be updated by build scripts
# when module definitions are parsed.
#
ALL_DEPENDENCY_DIRS :=

# this is the list of all generated files that we would need to clean
ALL_HOST_EXECUTABLES      :=
ALL_HOST_STATIC_LIBRARIES :=
ALL_STATIC_LIBRARIES      :=
ALL_SHARED_LIBRARIES      :=
ALL_EXECUTABLES           :=
ALL_INSTALLED_MODULES     :=

# the first rule
all: installed_modules host_libraries host_executables


$(foreach _app,$(NDK_APPS),\
  $(eval include $(BUILD_SYSTEM)/setup-app.mk)\
)

# ====================================================================
#
# Now finish the build preparation with a few rules that depend on
# what has been effectively parsed and recorded previously
#
# ====================================================================

clean: clean-intermediates clean-installed-modules

distclean: clean clean-config

installed_modules: libraries $(ALL_INSTALLED_MODULES)
host_libraries: $(HOST_STATIC_LIBRARIES)
host_executables: $(HOST_EXECUTABLES)

static_libraries: $(STATIC_LIBRARIES)
shared_libraries: $(SHARED_LIBRARIES)
executables: $(EXECUTABLES)

libraries: static_libraries shared_libraries

clean-host-intermediates:
	$(hide) rm -rf $(HOST_EXECUTABLES) $(HOST_STATIC_LIBRARIES)

clean-intermediates: clean-host-intermediates
	$(hide) rm -rf $(EXECUTABLES) $(STATIC_LIBRARIES) $(SHARED_LIBRARIES)

clean-installed-modules:
	$(hide) rm -rf $(ALL_INSTALLED_MODULES)

clean-config:
	$(hide) rm -f $(CONFIG_MAKE) $(CONFIG_H)

# include dependency information
ALL_DEPENDENCY_DIRS := $(sort $(ALL_DEPENDENCY_DIRS))
-include $(wildcard $(ALL_DEPENDENCY_DIRS:%=%/*.d))
