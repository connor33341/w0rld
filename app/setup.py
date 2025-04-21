from setuptools import setup, Extension
from Cython.Build import cythonize
import os

# Paths to libraries and includes (update with paths from setup.sh output)
include_dirs = [
    "vcpkg/installed/x64-linux/include",  # Update with $INSTALL_DIR/$VCPKG_TRIPLET/include
    "glad",  # Relative to app/
]
library_dirs = [
    "vcpkg/installed/x64-linux/lib",  # Update with $INSTALL_DIR/$VCPKG_TRIPLET/lib
]
libraries = ["openxr_loader", "glfw3", "opengl32", "Open3D"]

# Define the extension
extensions = [
    Extension(
        "app.openxr_point_cloud",  # Module name includes package
        sources=["openxr_point_cloud.pyx", "glad.c"],
        language="c++",
        include_dirs=include_dirs,
        library_dirs=library_dirs,
        libraries=libraries,
        extra_compile_args=["-std=c++11"] if os.name != "nt" else ["/std:c++17"],
    )
]

# Setup
setup(
    name="app",
    ext_modules=cythonize(extensions, compiler_directives={"language_level": "3"}),
)