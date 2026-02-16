# Makefile for CBZ Renamer (C++ version with cxxopts)

# Compiler
CXX = g++

# Compiler flags
CXXFLAGS = -std=c++17 -Wall -Wextra -O2 -Iinclude

# Directories
SRC_DIR = .
OBJ_DIR = obj
BIN_DIR = bin

# Executable name
TARGET = cbzr

# Source files
SRCS = $(SRC_DIR)/cbzr.cpp

# Object files (placed in obj/)
OBJS = $(OBJ_DIR)/$(notdir $(SRCS:.cpp=.o))

# PHONY targets
.PHONY: all build clean dirs

# Default target
all: build

# Ensure directories exist
dirs:
	mkdir -p $(OBJ_DIR) $(BIN_DIR)

# Build executable
build: dirs $(OBJS)
	$(CXX) $(CXXFLAGS) -o $(BIN_DIR)/$(TARGET) $(OBJS)

# Compile object files
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

# Clean build artifacts
clean:
	rm -rf $(OBJ_DIR)/* $(BIN_DIR)/$(TARGET)
