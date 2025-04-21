#!/bin/bash

# Exit on error
set -e

# Detect OS
OS=$(uname -s)
case "$OS" in
    Linux*)     OS_TYPE="Linux";;
    Darwin*)    OS_TYPE="macOS";;
    *)          echo "Unsupported OS: $OS"; exit 1;;
esac

# Config
USE_ENV="false" # Set to "true" if you want to use a Python virtual environment

# Define directories
VCPKG_DIR="vcpkg"
INSTALL_DIR="$(pwd)/vcpkg_installed"
GLAD_DIR="$(pwd)/glad"
PYTHON_ENV_DIR="$(pwd)/venv"
VCPKG_TRIPLET="x64-linux"
if [ "$OS_TYPE" = "macOS" ]; then
    VCPKG_TRIPLET="x64-osx"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting setup for vcpkg and libraries...${NC}"

# Step 1: Install system prerequisites
# sudo apt install libxinerama-dev libxcursor-dev xorg-dev libglu1-mesa-dev pkg-config
echo -e "${GREEN}Installing system prerequisites...${NC}"
if [ "$OS_TYPE" = "Linux" ]; then
    sudo apt-get update
    sudo apt-get install -y \
        git \
        curl \
        zip \
        unzip \
        tar \
        cmake \
        ninja-build \
        build-essential \
        python3 \
        python3-pip \
        python3-venv \
        libgl1-mesa-dev \
        libx11-dev \
        libxrandr-dev \
        libxinerama-dev \
        libxcursor-dev \
        libxi-dev \
        xorg-dev \
        pkg-config \
        libvulkan-dev \
        mesa-common-dev \
        libegl1-mesa-dev \
        libgles2-mesa-dev \

elif [ "$OS_TYPE" = "macOS" ]; then
    if ! command -v brew &> /dev/null; then
        echo -e "${RED}Homebrew not found. Installing Homebrew...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew install \
        git \
        curl \
        cmake \
        ninja \
        python3 \
        libpng \
        jpeg \
        eigen \
        tbb
fi

# Step 2: Install vcpkg
echo -e "${GREEN}Installing vcpkg...${NC}"
if [ ! -d "$VCPKG_DIR" ]; then
    git clone https://github.com/microsoft/vcpkg.git "$VCPKG_DIR"
else
    echo "vcpkg already exists at $VCPKG_DIR. Updating..."
    cd "$VCPKG_DIR"
    git pull
    cd -
fi

echo -e "${GREEN}Cleaning openxr-loader build directory...${NC}"
rm -rf "$VCPKG_DIR/buildtrees/openxr-loader"

cd "$VCPKG_DIR"
./bootstrap-vcpkg.sh
./vcpkg integrate install
cd -

# Step 3: Install libraries via vcpkg
echo -e "${GREEN}Installing libraries via vcpkg...${NC}"
"$VCPKG_DIR/vcpkg" install \
    openxr-loader:"$VCPKG_TRIPLET" \
    glfw3:"$VCPKG_TRIPLET" #\
    #open3d:"$VCPKG_TRIPLET"

# Step 4: Generate GLAD files
echo -e "${GREEN}Generating GLAD files...${NC}"
if [ ! -d "$GLAD_DIR" ]; then
    mkdir -p "$GLAD_DIR"
    # Download pre-generated GLAD files for OpenGL 3.3 core
    curl -L https://glad.dav1d.de/generated/tmp/OpenGL/glad.zip -o glad.zip
    unzip glad.zip -d "$GLAD_DIR"
    rm glad.zip
    mv "$GLAD_DIR/include" "$GLAD_DIR/glad"
    mv "$GLAD_DIR/src/glad.c" "$GLAD_DIR/"
else
    echo "GLAD directory already exists at $GLAD_DIR. Skipping download."
fi

# Step 5: Set up Python virtual environment
if [ "$USE_ENV" = "true" ]; then
    echo -e "${GREEN}Setting up Python virtual environment...${NC}"
    if [ ! -d "$PYTHON_ENV_DIR" ]; then
        python3 -m venv "$PYTHON_ENV_DIR"
    fi
    source "$PYTHON_ENV_DIR/bin/activate"
else
    echo -e "${GREEN}Not using a venv${NC}"
fi
pip install --upgrade pip
pip install cython numpy open3d

# Step 6: Configure environment variables
echo -e "${GREEN}Configuring environment variables...${NC}"
export VCPKG_ROOT="$VCPKG_DIR"
export LD_LIBRARY_PATH="$INSTALL_DIR/$VCPKG_TRIPLET/lib:$LD_LIBRARY_PATH"
export DYLD_LIBRARY_PATH="$INSTALL_DIR/$VCPKG_TRIPLET/lib:$DYLD_LIBRARY_PATH"
export CPLUS_INCLUDE_PATH="$INSTALL_DIR/$VCPKG_TRIPLET/include:$GLAD_DIR/glad:$CPLUS_INCLUDE_PATH"

# Persist environment variables
if [ "$OS_TYPE" = "Linux" ]; then
    echo "export VCPKG_ROOT=$VCPKG_DIR" >> ~/.bashrc
    echo "export LD_LIBRARY_PATH=$INSTALL_DIR/$VCPKG_TRIPLET/lib:\$LD_LIBRARY_PATH" >> ~/.bashrc
    echo "export CPLUS_INCLUDE_PATH=$INSTALL_DIR/$VCPKG_TRIPLET/include:$GLAD_DIR/glad:\$CPLUS_INCLUDE_PATH" >> ~/.bashrc
elif [ "$OS_TYPE" = "macOS" ]; then
    echo "export VCPKG_ROOT=$VCPKG_DIR" >> ~/.zshrc
    echo "export DYLD_LIBRARY_PATH=$INSTALL_DIR/$VCPKG_TRIPLET/lib:\$DYLD_LIBRARY_PATH" >> ~/.zshrc
    echo "export CPLUS_INCLUDE_PATH=$INSTALL_DIR/$VCPKG_TRIPLET/include:$GLAD_DIR/glad:\$CPLUS_INCLUDE_PATH" >> ~/.zshrc
fi

# Step 7: Provide instructions for setup.py
echo -e "${GREEN}Setup complete! Next steps:${NC}"
echo "1. Update your setup.py with the following paths:"
echo "   include_dirs: ["
echo "       '$INSTALL_DIR/$VCPKG_TRIPLET/include',"
echo "       '$GLAD_DIR/glad',"
echo "   ]"
echo "   library_dirs: ["
echo "       '$INSTALL_DIR/$VCPKG_TRIPLET/lib',"
echo "   ]"
echo "2. Ensure glad.c is in the same directory as openxr_point_cloud.pyx."
echo "3. Run 'python setup.py build_ext --inplace' to compile the Cython module."
echo "4. Activate the Python environment: 'source $PYTHON_ENV_DIR/bin/activate'"
echo "5. Run the main Python script: 'python main.py'"
echo -e "${GREEN}Environment variables have been added to your shell configuration. Restart your terminal or source ~/.bashrc (Linux) or ~/.zshrc (macOS).${NC}"

# Step 8: Copy GLAD files to current directory
echo -e "${GREEN}Copying GLAD files to current directory...${NC}"
cp "$GLAD_DIR/glad.c" .
cp -r "$GLAD_DIR/glad" .

deactivate