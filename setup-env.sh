#!/bin/bash

# GreenThumb Environment Setup Script
# This script configures the environment to use the local Racket 6.7 installation
# instead of the system-wide Racket installation

# Set the path to the local Racket 6.7 installation
export PATH=/home/allenjin/Codes/greenthumb/tools/racket-6.7/bin:$PATH

# Verify the correct Racket version is being used
echo "Setting up GreenThumb environment..."
echo "Racket version: $(racket --version)"
echo "Racket path: $(which racket)"
echo "Raco path: $(which raco)"

# Optional: Set PLTHOME if needed by some Racket tools
export PLTHOME=/home/allenjin/Codes/greenthumb/tools/racket-6.7

echo ""
echo "GreenThumb environment ready!"
echo "You can now run GreenThumb commands in this session."