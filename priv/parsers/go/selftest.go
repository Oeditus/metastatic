package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
)

// selftest exercises parse, JSON and structural reification without depending
// on any external tools or packages. An optional directory is scanned for .go
// files as an additional local smoke test.
func selftest(directory string) Response {
	samples := []string{
		"1 + 2",
		"package p\nfunc Map[T any](xs []T) []T { return xs }\n",
		"//go:build linux\n\npackage p\n// F documents F.\nfunc F() { x, y := 1, 2; _, _ = x, y }\n",
	}
	if directory != "" {
		err := filepath.WalkDir(directory, func(path string, entry os.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if !entry.IsDir() && filepath.Ext(path) == ".go" {
				bytes, err := os.ReadFile(path)
				if err != nil {
					return err
				}
				samples = append(samples, string(bytes))
			}
			return nil
		})
		if err != nil {
			return ErrorResponse("SelftestError", err.Error(), 0)
		}
	}
	for _, source := range samples {
		parsed := parseSource(source)
		if !parsed.OK {
			return parsed
		}
		payload, err := json.Marshal(parsed.AST)
		if err != nil {
			return ErrorResponse("SelftestError", err.Error(), 0)
		}
		printed := unparseSource(string(payload))
		if !printed.OK {
			return printed
		}
		if reparsed := parseSource(printed.Source); !reparsed.OK {
			return reparsed
		}
	}
	return ASTResponse(map[string]any{"status": "ok", "tests": len(samples), "go_version": runtime.Version()})
}
