cmake_minimum_required(VERSION 3.21)
project(blankos-game-hub VERSION 1.0 LANGUAGES CXX)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(blankos-game-hub main.cpp flatpak.cpp flatpak.h)
qt_add_qml_module(blankos-game-hub
    URI BlankOS.GameHub
    VERSION 1.0
    QML_FILES Main.qml
    NO_RESOURCE_TARGET_PATH
)
target_link_libraries(blankos-game-hub PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick)

include(GNUInstallDirs)
install(TARGETS blankos-game-hub RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.blankos.GameHub.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES blankos-game-hub-autostart.desktop DESTINATION /etc/xdg/autostart)
