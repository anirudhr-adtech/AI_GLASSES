#!/bin/bash
###############################################################################
# Install Open-Source Physical Design Tools + SKY130 PDK
# Usage: bash scripts/install_tools.sh
#
# Tools installed:
#   - Yosys       (RTL synthesis)
#   - OpenSTA     (static timing analysis)
#   - OpenROAD    (floorplan + placement + CTS + routing)
#   - Magic       (layout viewer + DRC)
#   - Netgen      (LVS)
#   - KLayout     (layout viewer)
#   - SKY130 PDK  (via volare)
###############################################################################

set -e

echo "============================================"
echo " AI Glasses SoC — PD Tool Installation"
echo "============================================"

# ----------------------------------------------------------------------
# System dependencies
# ----------------------------------------------------------------------
echo "[1/8] Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    build-essential clang bison flex \
    libreadline-dev gawk tcl-dev libffi-dev \
    git graphviz xdot pkg-config python3 \
    python3-pip python3-venv \
    libboost-all-dev cmake \
    zlib1g-dev libcairo2-dev \
    tk-dev libgsl-dev \
    swig libeigen3-dev \
    lemon

# ----------------------------------------------------------------------
# Yosys
# ----------------------------------------------------------------------
echo "[2/8] Installing Yosys..."
if which yosys >/dev/null 2>&1; then
    echo "  Yosys already installed: $(yosys --version 2>/dev/null | head -1)"
else
    sudo apt-get install -y -qq yosys 2>/dev/null || {
        echo "  Building Yosys from source..."
        cd /tmp
        git clone --depth 1 https://github.com/YosysHQ/yosys.git yosys-build
        cd yosys-build
        make -j$(nproc)
        sudo make install
        cd /tmp && rm -rf yosys-build
    }
fi

# ----------------------------------------------------------------------
# OpenSTA
# ----------------------------------------------------------------------
echo "[3/8] Installing OpenSTA..."
if which sta >/dev/null 2>&1; then
    echo "  OpenSTA already installed"
else
    cd /tmp
    git clone --depth 1 https://github.com/The-OpenROAD-Project/OpenSTA.git opensta-build
    cd opensta-build
    mkdir build && cd build
    cmake ..
    make -j$(nproc)
    sudo make install
    cd /tmp && rm -rf opensta-build
fi

# ----------------------------------------------------------------------
# OpenROAD
# ----------------------------------------------------------------------
echo "[4/8] Installing OpenROAD..."
if which openroad >/dev/null 2>&1; then
    echo "  OpenROAD already installed"
else
    echo "  Installing OpenROAD via pre-built package..."
    # Try the OpenROAD installer script
    cd /tmp
    git clone --depth 1 --recursive https://github.com/The-OpenROAD-Project/OpenROAD.git openroad-build
    cd openroad-build
    sudo ./etc/DependencyInstaller.sh
    mkdir build && cd build
    cmake ..
    make -j$(nproc)
    sudo make install
    cd /tmp && rm -rf openroad-build
fi

# ----------------------------------------------------------------------
# Magic
# ----------------------------------------------------------------------
echo "[5/8] Installing Magic..."
if which magic >/dev/null 2>&1; then
    echo "  Magic already installed: $(magic --version 2>/dev/null | head -1)"
else
    sudo apt-get install -y -qq magic 2>/dev/null || {
        cd /tmp
        git clone --depth 1 https://github.com/RTimothyEdwards/magic.git magic-build
        cd magic-build
        ./configure
        make -j$(nproc)
        sudo make install
        cd /tmp && rm -rf magic-build
    }
fi

# ----------------------------------------------------------------------
# Netgen
# ----------------------------------------------------------------------
echo "[6/8] Installing Netgen..."
if which netgen >/dev/null 2>&1; then
    echo "  Netgen already installed"
else
    sudo apt-get install -y -qq netgen-lvs 2>/dev/null || {
        cd /tmp
        git clone --depth 1 https://github.com/RTimothyEdwards/netgen.git netgen-build
        cd netgen-build
        ./configure
        make -j$(nproc)
        sudo make install
        cd /tmp && rm -rf netgen-build
    }
fi

# ----------------------------------------------------------------------
# KLayout (optional viewer)
# ----------------------------------------------------------------------
echo "[7/8] Installing KLayout..."
if which klayout >/dev/null 2>&1; then
    echo "  KLayout already installed"
else
    sudo apt-get install -y -qq klayout 2>/dev/null || {
        echo "  KLayout not available via apt — install manually from klayout.de"
    }
fi

# ----------------------------------------------------------------------
# SKY130 PDK via volare
# ----------------------------------------------------------------------
echo "[8/8] Installing SKY130 PDK..."
pip3 install --user volare 2>/dev/null || pip3 install volare

export PDK_ROOT="${PDK_ROOT:-$HOME/.volare}"
echo "  PDK_ROOT=${PDK_ROOT}"

if [ -f "${PDK_ROOT}/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib" ]; then
    echo "  SKY130 PDK already installed"
else
    echo "  Downloading SKY130 PDK (this may take a while)..."
    volare enable --pdk sky130 78b7bc32ddb4b6f14f76883c2e2dc5b5de9d1cbc
fi

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------
echo ""
echo "============================================"
echo " Installation Summary"
echo "============================================"
echo ""
which yosys    >/dev/null 2>&1 && echo "  [OK] yosys"    || echo "  [FAIL] yosys"
which sta      >/dev/null 2>&1 && echo "  [OK] OpenSTA"  || echo "  [FAIL] OpenSTA"
which openroad >/dev/null 2>&1 && echo "  [OK] openroad" || echo "  [FAIL] openroad"
which magic    >/dev/null 2>&1 && echo "  [OK] magic"    || echo "  [FAIL] magic"
which netgen   >/dev/null 2>&1 && echo "  [OK] netgen"   || echo "  [FAIL] netgen"
which klayout  >/dev/null 2>&1 && echo "  [OK] klayout"  || echo "  [SKIP] klayout"
echo ""
echo "Add to your shell profile:"
echo "  export PDK_ROOT=${PDK_ROOT}"
echo ""
echo "Then run: cd pd && make check_tools && make check_pdk"
