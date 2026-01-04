cmake_minimum_required(VERSION 3.16)
project(xembedsniproxy)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(ECMQtDeclareLoggingCategory)

find_package(Qt6 REQUIRED COMPONENTS Core DBus)
find_package(KF6WindowSystem REQUIRED)
find_package(KF6DBusAddons REQUIRED)
find_package(KF6CoreAddons REQUIRED)
find_package(KF6Crash REQUIRED)
find_package(X11 REQUIRED)
find_package(XCB REQUIRED COMPONENTS
    XCB XFIXES DAMAGE COMPOSITE RANDR SHM UTIL IMAGE
)

set(XCB_LIBS
    XCB::XCB XCB::XFIXES XCB::DAMAGE XCB::COMPOSITE
    XCB::RANDR XCB::SHM XCB::UTIL XCB::IMAGE
)

set(XEMBED_SNI_PROXY_SOURCES
    main.cpp
    fdoselectionmanager.cpp
    snidbus.cpp
    sniproxy.cpp
    xtestsender.cpp
)

qt_add_dbus_adaptor(XEMBED_SNI_PROXY_SOURCES org.kde.StatusNotifierItem.xml sniproxy.h SNIProxy)
qt_add_dbus_interface(XEMBED_SNI_PROXY_SOURCES org.kde.StatusNotifierWatcher.xml statusnotifierwatcher_interface)

ecm_qt_declare_logging_category(XEMBED_SNI_PROXY_SOURCES
    HEADER debug.h
    IDENTIFIER SNIPROXY
    CATEGORY_NAME kde.xembedsniproxy
    DEFAULT_SEVERITY Info
    DESCRIPTION "xembed sni proxy"
)

add_executable(xembedsniproxy ${XEMBED_SNI_PROXY_SOURCES})

target_include_directories(xembedsniproxy PRIVATE ${CMAKE_CURRENT_BINARY_DIR} ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(xembedsniproxy
    Qt6::Core
    Qt6::DBus
    KF6::DBusAddons
    KF6::WindowSystem
    KF6::CoreAddons
    KF6::Crash
    ${XCB_LIBS}
    X11::Xtst
)

install(TARGETS xembedsniproxy DESTINATION bin)
