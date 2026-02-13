defmodule Metastatic.Semantic.Domains.File do
  @moduledoc """
  File I/O operation patterns for semantic enrichment.

  This module defines patterns for detecting file operations across
  multiple languages and file handling libraries. Patterns are registered with
  the `Metastatic.Semantic.Patterns` registry at module load time.

  ## Supported Libraries

  ### Elixir
  - **File** - Standard library file operations
  - **Path** - Path manipulation
  - **IO** - Input/output operations

  ### Python
  - **builtins** - open(), read(), write()
  - **os** - OS-level file operations
  - **pathlib** - Object-oriented path operations
  - **shutil** - High-level file operations

  ### Ruby
  - **File** - Standard library file operations
  - **FileUtils** - File utility methods
  - **IO** - Input/output operations

  ### JavaScript
  - **fs** - Node.js file system module
  - **fs/promises** - Promise-based fs operations
  - **path** - Path manipulation

  ## File Operations

  | Operation | Description |
  |-----------|-------------|
  | `:read` | Read file contents |
  | `:write` | Write to file |
  | `:append` | Append to file |
  | `:delete` | Delete file |
  | `:copy` | Copy file |
  | `:move` | Move/rename file |
  | `:exists` | Check if file exists |
  | `:stat` | Get file metadata |
  | `:mkdir` | Create directory |
  | `:rmdir` | Remove directory |
  | `:list` | List directory contents |
  | `:open` | Open file handle |
  | `:close` | Close file handle |

  ## Pattern Structure

  Each pattern is a tuple of `{pattern, spec}` where:
  - `pattern` - String or Regex to match function names
  - `spec` - Map with operation details:
    - `:operation` - The file operation type
    - `:framework` - The file library identifier
    - `:extract_target` - Strategy for extracting file path
  """

  alias Metastatic.Semantic.Patterns

  # ----- Elixir/File Patterns -----

  @elixir_file_patterns [
    {"File.read", %{operation: :read, framework: :elixir_file, extract_target: :first_arg}},
    {"File.read!", %{operation: :read, framework: :elixir_file, extract_target: :first_arg}},
    {"File.write", %{operation: :write, framework: :elixir_file, extract_target: :first_arg}},
    {"File.write!", %{operation: :write, framework: :elixir_file, extract_target: :first_arg}},
    {"File.open", %{operation: :open, framework: :elixir_file, extract_target: :first_arg}},
    {"File.open!", %{operation: :open, framework: :elixir_file, extract_target: :first_arg}},
    {"File.close", %{operation: :close, framework: :elixir_file, extract_target: :first_arg}},
    {"File.rm", %{operation: :delete, framework: :elixir_file, extract_target: :first_arg}},
    {"File.rm!", %{operation: :delete, framework: :elixir_file, extract_target: :first_arg}},
    {"File.rm_rf", %{operation: :delete, framework: :elixir_file, extract_target: :first_arg}},
    {"File.rm_rf!", %{operation: :delete, framework: :elixir_file, extract_target: :first_arg}},
    {"File.cp", %{operation: :copy, framework: :elixir_file, extract_target: :first_arg}},
    {"File.cp!", %{operation: :copy, framework: :elixir_file, extract_target: :first_arg}},
    {"File.cp_r", %{operation: :copy, framework: :elixir_file, extract_target: :first_arg}},
    {"File.cp_r!", %{operation: :copy, framework: :elixir_file, extract_target: :first_arg}},
    {"File.rename", %{operation: :move, framework: :elixir_file, extract_target: :first_arg}},
    {"File.rename!", %{operation: :move, framework: :elixir_file, extract_target: :first_arg}},
    {"File.exists?", %{operation: :exists, framework: :elixir_file, extract_target: :first_arg}},
    {"File.stat", %{operation: :stat, framework: :elixir_file, extract_target: :first_arg}},
    {"File.stat!", %{operation: :stat, framework: :elixir_file, extract_target: :first_arg}},
    {"File.mkdir", %{operation: :mkdir, framework: :elixir_file, extract_target: :first_arg}},
    {"File.mkdir!", %{operation: :mkdir, framework: :elixir_file, extract_target: :first_arg}},
    {"File.mkdir_p", %{operation: :mkdir, framework: :elixir_file, extract_target: :first_arg}},
    {"File.mkdir_p!", %{operation: :mkdir, framework: :elixir_file, extract_target: :first_arg}},
    {"File.rmdir", %{operation: :rmdir, framework: :elixir_file, extract_target: :first_arg}},
    {"File.rmdir!", %{operation: :rmdir, framework: :elixir_file, extract_target: :first_arg}},
    {"File.ls", %{operation: :list, framework: :elixir_file, extract_target: :first_arg}},
    {"File.ls!", %{operation: :list, framework: :elixir_file, extract_target: :first_arg}},
    {"File.stream!", %{operation: :read, framework: :elixir_file, extract_target: :first_arg}}
  ]

  # ----- Elixir/IO Patterns -----

  @elixir_io_patterns [
    {"IO.read", %{operation: :read, framework: :elixir_io, extract_target: :first_arg}},
    {"IO.write", %{operation: :write, framework: :elixir_io, extract_target: :first_arg}},
    {"IO.binread", %{operation: :read, framework: :elixir_io, extract_target: :first_arg}},
    {"IO.binwrite", %{operation: :write, framework: :elixir_io, extract_target: :first_arg}},
    {"IO.gets", %{operation: :read, framework: :elixir_io, extract_target: :first_arg}},
    {"IO.puts", %{operation: :write, framework: :elixir_io, extract_target: :first_arg}}
  ]

  # ----- Python/builtins Patterns -----

  @python_builtin_patterns [
    {"open", %{operation: :open, framework: :python_builtin, extract_target: :first_arg}},
    {"file.read", %{operation: :read, framework: :python_builtin, extract_target: :none}},
    {"file.write", %{operation: :write, framework: :python_builtin, extract_target: :none}},
    {"file.close", %{operation: :close, framework: :python_builtin, extract_target: :none}},
    {"file.readline", %{operation: :read, framework: :python_builtin, extract_target: :none}},
    {"file.readlines", %{operation: :read, framework: :python_builtin, extract_target: :none}},
    {"file.writelines", %{operation: :write, framework: :python_builtin, extract_target: :none}},
    {"f.read", %{operation: :read, framework: :python_builtin, extract_target: :none}},
    {"f.write", %{operation: :write, framework: :python_builtin, extract_target: :none}},
    {"f.close", %{operation: :close, framework: :python_builtin, extract_target: :none}}
  ]

  # ----- Python/os Patterns -----

  @python_os_patterns [
    {"os.remove", %{operation: :delete, framework: :python_os, extract_target: :first_arg}},
    {"os.unlink", %{operation: :delete, framework: :python_os, extract_target: :first_arg}},
    {"os.rename", %{operation: :move, framework: :python_os, extract_target: :first_arg}},
    {"os.replace", %{operation: :move, framework: :python_os, extract_target: :first_arg}},
    {"os.mkdir", %{operation: :mkdir, framework: :python_os, extract_target: :first_arg}},
    {"os.makedirs", %{operation: :mkdir, framework: :python_os, extract_target: :first_arg}},
    {"os.rmdir", %{operation: :rmdir, framework: :python_os, extract_target: :first_arg}},
    {"os.removedirs", %{operation: :rmdir, framework: :python_os, extract_target: :first_arg}},
    {"os.listdir", %{operation: :list, framework: :python_os, extract_target: :first_arg}},
    {"os.scandir", %{operation: :list, framework: :python_os, extract_target: :first_arg}},
    {"os.stat", %{operation: :stat, framework: :python_os, extract_target: :first_arg}},
    {"os.path.exists", %{operation: :exists, framework: :python_os, extract_target: :first_arg}},
    {"os.path.isfile", %{operation: :exists, framework: :python_os, extract_target: :first_arg}},
    {"os.path.isdir", %{operation: :exists, framework: :python_os, extract_target: :first_arg}}
  ]

  # ----- Python/pathlib Patterns -----

  @python_pathlib_patterns [
    {~r/\.read_text$/, %{operation: :read, framework: :pathlib, extract_target: :receiver}},
    {~r/\.read_bytes$/, %{operation: :read, framework: :pathlib, extract_target: :receiver}},
    {~r/\.write_text$/, %{operation: :write, framework: :pathlib, extract_target: :receiver}},
    {~r/\.write_bytes$/, %{operation: :write, framework: :pathlib, extract_target: :receiver}},
    {~r/\.unlink$/, %{operation: :delete, framework: :pathlib, extract_target: :receiver}},
    {~r/\.rename$/, %{operation: :move, framework: :pathlib, extract_target: :receiver}},
    {~r/\.replace$/, %{operation: :move, framework: :pathlib, extract_target: :receiver}},
    {~r/\.mkdir$/, %{operation: :mkdir, framework: :pathlib, extract_target: :receiver}},
    {~r/\.rmdir$/, %{operation: :rmdir, framework: :pathlib, extract_target: :receiver}},
    {~r/\.iterdir$/, %{operation: :list, framework: :pathlib, extract_target: :receiver}},
    {~r/\.exists$/, %{operation: :exists, framework: :pathlib, extract_target: :receiver}},
    {~r/\.is_file$/, %{operation: :exists, framework: :pathlib, extract_target: :receiver}},
    {~r/\.is_dir$/, %{operation: :exists, framework: :pathlib, extract_target: :receiver}},
    {~r/\.stat$/, %{operation: :stat, framework: :pathlib, extract_target: :receiver}},
    {~r/\.open$/, %{operation: :open, framework: :pathlib, extract_target: :receiver}},
    {"Path", %{operation: :stat, framework: :pathlib, extract_target: :first_arg}}
  ]

  # ----- Python/shutil Patterns -----

  @python_shutil_patterns [
    {"shutil.copy", %{operation: :copy, framework: :shutil, extract_target: :first_arg}},
    {"shutil.copy2", %{operation: :copy, framework: :shutil, extract_target: :first_arg}},
    {"shutil.copyfile", %{operation: :copy, framework: :shutil, extract_target: :first_arg}},
    {"shutil.copytree", %{operation: :copy, framework: :shutil, extract_target: :first_arg}},
    {"shutil.move", %{operation: :move, framework: :shutil, extract_target: :first_arg}},
    {"shutil.rmtree", %{operation: :delete, framework: :shutil, extract_target: :first_arg}}
  ]

  # ----- Ruby/File Patterns -----

  @ruby_file_patterns [
    {"File.read", %{operation: :read, framework: :ruby_file, extract_target: :first_arg}},
    {"File.write", %{operation: :write, framework: :ruby_file, extract_target: :first_arg}},
    {"File.open", %{operation: :open, framework: :ruby_file, extract_target: :first_arg}},
    {"File.delete", %{operation: :delete, framework: :ruby_file, extract_target: :first_arg}},
    {"File.unlink", %{operation: :delete, framework: :ruby_file, extract_target: :first_arg}},
    {"File.rename", %{operation: :move, framework: :ruby_file, extract_target: :first_arg}},
    {"File.exist?", %{operation: :exists, framework: :ruby_file, extract_target: :first_arg}},
    {"File.exists?", %{operation: :exists, framework: :ruby_file, extract_target: :first_arg}},
    {"File.file?", %{operation: :exists, framework: :ruby_file, extract_target: :first_arg}},
    {"File.directory?", %{operation: :exists, framework: :ruby_file, extract_target: :first_arg}},
    {"File.stat", %{operation: :stat, framework: :ruby_file, extract_target: :first_arg}},
    {"File.size", %{operation: :stat, framework: :ruby_file, extract_target: :first_arg}},
    {"Dir.mkdir", %{operation: :mkdir, framework: :ruby_file, extract_target: :first_arg}},
    {"Dir.rmdir", %{operation: :rmdir, framework: :ruby_file, extract_target: :first_arg}},
    {"Dir.delete", %{operation: :rmdir, framework: :ruby_file, extract_target: :first_arg}},
    {"Dir.entries", %{operation: :list, framework: :ruby_file, extract_target: :first_arg}},
    {"Dir.glob", %{operation: :list, framework: :ruby_file, extract_target: :first_arg}},
    {"Dir.foreach", %{operation: :list, framework: :ruby_file, extract_target: :first_arg}}
  ]

  # ----- Ruby/FileUtils Patterns -----

  @ruby_fileutils_patterns [
    {"FileUtils.cp", %{operation: :copy, framework: :fileutils, extract_target: :first_arg}},
    {"FileUtils.copy", %{operation: :copy, framework: :fileutils, extract_target: :first_arg}},
    {"FileUtils.cp_r", %{operation: :copy, framework: :fileutils, extract_target: :first_arg}},
    {"FileUtils.mv", %{operation: :move, framework: :fileutils, extract_target: :first_arg}},
    {"FileUtils.move", %{operation: :move, framework: :fileutils, extract_target: :first_arg}},
    {"FileUtils.rm", %{operation: :delete, framework: :fileutils, extract_target: :first_arg}},
    {"FileUtils.rm_f", %{operation: :delete, framework: :fileutils, extract_target: :first_arg}},
    {"FileUtils.rm_r", %{operation: :delete, framework: :fileutils, extract_target: :first_arg}},
    {"FileUtils.rm_rf", %{operation: :delete, framework: :fileutils, extract_target: :first_arg}},
    {"FileUtils.mkdir", %{operation: :mkdir, framework: :fileutils, extract_target: :first_arg}},
    {"FileUtils.mkdir_p",
     %{operation: :mkdir, framework: :fileutils, extract_target: :first_arg}},
    {"FileUtils.rmdir", %{operation: :rmdir, framework: :fileutils, extract_target: :first_arg}},
    {"FileUtils.touch", %{operation: :write, framework: :fileutils, extract_target: :first_arg}}
  ]

  # ----- JavaScript/fs Patterns -----

  @javascript_fs_patterns [
    {"fs.readFile", %{operation: :read, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.readFileSync", %{operation: :read, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.writeFile", %{operation: :write, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.writeFileSync", %{operation: :write, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.appendFile", %{operation: :append, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.appendFileSync",
     %{operation: :append, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.unlink", %{operation: :delete, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.unlinkSync", %{operation: :delete, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.rm", %{operation: :delete, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.rmSync", %{operation: :delete, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.copyFile", %{operation: :copy, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.copyFileSync", %{operation: :copy, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.cp", %{operation: :copy, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.cpSync", %{operation: :copy, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.rename", %{operation: :move, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.renameSync", %{operation: :move, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.existsSync", %{operation: :exists, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.stat", %{operation: :stat, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.statSync", %{operation: :stat, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.lstat", %{operation: :stat, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.lstatSync", %{operation: :stat, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.mkdir", %{operation: :mkdir, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.mkdirSync", %{operation: :mkdir, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.rmdir", %{operation: :rmdir, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.rmdirSync", %{operation: :rmdir, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.readdir", %{operation: :list, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.readdirSync", %{operation: :list, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.open", %{operation: :open, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.openSync", %{operation: :open, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.close", %{operation: :close, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.closeSync", %{operation: :close, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.createReadStream",
     %{operation: :read, framework: :nodejs_fs, extract_target: :first_arg}},
    {"fs.createWriteStream",
     %{operation: :write, framework: :nodejs_fs, extract_target: :first_arg}}
  ]

  # ----- JavaScript/fs/promises Patterns -----

  @javascript_fspromises_patterns [
    {"fsPromises.readFile",
     %{operation: :read, framework: :nodejs_fs_promises, extract_target: :first_arg}},
    {"fsPromises.writeFile",
     %{operation: :write, framework: :nodejs_fs_promises, extract_target: :first_arg}},
    {"fsPromises.appendFile",
     %{operation: :append, framework: :nodejs_fs_promises, extract_target: :first_arg}},
    {"fsPromises.unlink",
     %{operation: :delete, framework: :nodejs_fs_promises, extract_target: :first_arg}},
    {"fsPromises.rm",
     %{operation: :delete, framework: :nodejs_fs_promises, extract_target: :first_arg}},
    {"fsPromises.copyFile",
     %{operation: :copy, framework: :nodejs_fs_promises, extract_target: :first_arg}},
    {"fsPromises.cp",
     %{operation: :copy, framework: :nodejs_fs_promises, extract_target: :first_arg}},
    {"fsPromises.rename",
     %{operation: :move, framework: :nodejs_fs_promises, extract_target: :first_arg}},
    {"fsPromises.stat",
     %{operation: :stat, framework: :nodejs_fs_promises, extract_target: :first_arg}},
    {"fsPromises.mkdir",
     %{operation: :mkdir, framework: :nodejs_fs_promises, extract_target: :first_arg}},
    {"fsPromises.rmdir",
     %{operation: :rmdir, framework: :nodejs_fs_promises, extract_target: :first_arg}},
    {"fsPromises.readdir",
     %{operation: :list, framework: :nodejs_fs_promises, extract_target: :first_arg}},
    {"fsPromises.open",
     %{operation: :open, framework: :nodejs_fs_promises, extract_target: :first_arg}},
    {"fsPromises.access",
     %{operation: :exists, framework: :nodejs_fs_promises, extract_target: :first_arg}}
  ]

  # ----- Registration -----

  @doc """
  Registers all file patterns for all languages.

  Called automatically when the module is loaded. Can also be called
  manually to re-register patterns (e.g., after clearing).
  """
  @spec register_all() :: :ok
  def register_all do
    # Elixir patterns (File + IO)
    Patterns.register(
      :file,
      :elixir,
      @elixir_file_patterns ++ @elixir_io_patterns
    )

    # Python patterns (builtins + os + pathlib + shutil)
    Patterns.register(
      :file,
      :python,
      @python_builtin_patterns ++
        @python_os_patterns ++ @python_pathlib_patterns ++ @python_shutil_patterns
    )

    # Ruby patterns (File + FileUtils)
    Patterns.register(
      :file,
      :ruby,
      @ruby_file_patterns ++ @ruby_fileutils_patterns
    )

    # JavaScript patterns (fs + fs/promises)
    Patterns.register(
      :file,
      :javascript,
      @javascript_fs_patterns ++ @javascript_fspromises_patterns
    )

    :ok
  end

  @doc false
  def __on_definition__(_env, _kind, _name, _args, _guards, _body) do
    :ok
  end
end

# Register patterns when module is loaded
Metastatic.Semantic.Domains.File.register_all()
