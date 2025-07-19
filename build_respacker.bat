@echo off
odin build src/game/respacker -o:aggressive -out:build/respacker.exe -vet-style -vet-shadowing -vet-using-stmt -vet-using-param -vet-semicolon
