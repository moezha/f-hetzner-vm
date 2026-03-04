.PHONY: help install

# Default target when you just type 'make'
help:
	@echo "Available commands:"
	@echo "  make install  - Grants execute permissions and runs the automated server setup"

# The main entry point
install:
	@echo "Preparing scripts..."
	chmod +x setup.sh scripts/*.sh
	@echo "Starting server provisioning..."
	./setup.sh