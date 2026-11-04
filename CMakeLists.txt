cmake_minimum_required(VERSION 3.21)
project(D3RCode VERSION 1.0.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Gui Qml Quick)
qt_standard_project_setup()

qt_add_executable(D3RCode WIN32
    src/main.cpp src/sys.cpp src/sys.h src/lsp.cpp src/lsp.h src/highlighter.cpp src/highlighter.h)
if(WIN32)
    target_sources(D3RCode PRIVATE app.rc)        # значок .exe
    target_link_libraries(D3RCode PRIVATE psapi)  # GetProcessMemoryInfo — пиковая память программы
    target_compile_definitions(D3RCode PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
endif()
qt_add_resources(D3RCode qml PREFIX "/" BASE qml FILES
    qml/Code.qml qml/Editor.qml qml/TreeNode.qml qml/ToolTipBox.qml qml/themes.js qml/pyhelper.py qml/icon.png)
qt_add_resources(D3RCode fonts PREFIX "/" FILES fonts/FiraCodeNerdFontMono-Regular.ttf)
target_link_libraries(D3RCode PRIVATE Qt6::Gui Qt6::Qml Qt6::Quick)
