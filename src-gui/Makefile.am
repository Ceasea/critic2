# binary and sources
bin_PROGRAMS = gcritic2
gcritic2_SOURCES = main.cpp view.cpp scene.cpp shapes.cpp keybinding.cpp settings.cpp dialog.cpp message.cpp menu.cpp tree.cpp text.cpp

# subdirectories
SUBDIRS=imgui .

# static libraries
gcritic2_LDADD=$(top_srcdir)/src/libcritic2.a \
	$(top_srcdir)/src/oldlibs/libmisc.a \
	$(top_srcdir)/src/ciftbx/libciftbx.a \
	$(top_srcdir)/src/cubpack/libcubpack.a \
	$(top_srcdir)/src/spglib/libspglib.a \
	$(top_srcdir)/src/qhull/libqhull_critic.a \
	imgui/imgui.o imgui/imgui_draw.o imgui/imgui_impl_glfw_gl3.o \
	imgui/imgui_demo.o imgui/imgui_dock.o imgui/imgui_widgets.o \
	imgui/gl3w.o $(LIBADD)

gcritic2_DEPENDENCIES=$(gcritic2_LDADD)

# Include the header files
## -lquadmath : for libCINT
AM_CXXFLAGS=-I$(top_srcdir)/include `pkg-config --cflags glfw3 gl freetype2 glm` -Wall -Wformat -D_GLIBCXX_USE_CXX11_ABI=0 -std=c++11 -w -g
AM_LDFLAGS=-ldl -lgfortran -lgomp -lquadmath `pkg-config --libs glfw3 gl freetype2 glm`
