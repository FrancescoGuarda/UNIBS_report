--[[
unibs.lua -- cross-platform entry point of the UNIBS weekly-report suite.

Runs with the Lua interpreter embedded in pandoc (no Python/shell needed):

  pandoc lua scripts/unibs.lua <command> [args]

Commands:
  report [FILE...]   PDF of the given reports (default: most recent one)
  compendium         PDF of the compendium
  all                PDF of every report + compendium
  new [YY-MM-DD]     new weekly-reports/YY-MM-DD.md from templates/YY-MM-DD.md
                     (default: today)
  cover              new cover.md from templates/cover_template.md
                     (fails if cover.md already exists)
  assets             re-render res/*.svg to PDF (needs rsvg-convert)
  help               this help

Works from any working directory: paths are resolved from the project root
(parent of scripts/). Set the PANDOC environment variable to use a pandoc
executable that is not on PATH.
]]

local path = pandoc.path
local system = pandoc.system

PANDOC_VERSION:must_be_at_least '3.1'

local PANDOC = os.getenv('PANDOC') or 'pandoc'
local CWD = system.get_working_directory()

local function absolute(p)
  if path.is_relative(p) then p = path.join { CWD, p } end
  return path.normalize(p)
end

local ROOT = path.directory(path.directory(absolute(arg[0])))
local REPORTS = path.join { ROOT, 'weekly-reports' }
local OUTDIR = path.join { ROOT, 'weekly_reports_pdf' }
local TEMPLATES = path.join { ROOT, 'templates' }
local DATA = path.join { ROOT, 'DATA.yaml' }
local COVER = path.join { ROOT, 'cover.md' }
local REPORT_PATTERN = '^%d%d%-%d%d%-%d%d%.md$'

local function say(msg) io.stdout:write(msg .. '\n'); io.stdout:flush() end
local function fail(msg) io.stderr:write('Errore: ' .. msg .. '\n'); os.exit(1) end

local function exists(p)
  local fh = io.open(p, 'rb')
  if fh then fh:close() return true end
  return false
end

local function read_file(p)
  local fh = assert(io.open(p, 'rb'))
  local s = fh:read('a'); fh:close(); return s
end

local function write_file(p, s)
  local fh = assert(io.open(p, 'wb'))
  fh:write(s); fh:close()
end

--- Runs a program from the project root; stderr goes straight to the terminal.
local function run(cmd, args)
  local ok, err = pcall(system.with_working_directory, ROOT, function()
    return pandoc.pipe(cmd, args, '')
  end)
  if not ok then
    local detail = type(err) == 'table' and ('codice ' .. tostring(err.error_code)) or tostring(err)
    fail(string.format('%s non riuscito (%s). Vedi i messaggi sopra.', cmd, detail))
  end
end

local function report_files()
  local files = pandoc.List()
  for _, name in ipairs(system.list_directory(REPORTS)) do
    if name:match(REPORT_PATTERN) then files:insert(name) end
  end
  table.sort(files)
  return files
end

--- Stops with a hint when a file the pipeline needs is missing.
local function require_file(p, hint)
  if not exists(p) then
    fail('manca ' .. path.make_relative(p, ROOT) .. ': ' .. hint)
  end
end

local function require_data()
  require_file(DATA, 'copia templates/DATA_template.yaml in DATA.yaml e compilalo')
end

--- Copies a template to `target`, refusing to overwrite; `edit` may rewrite the text.
local function from_template(template, target, edit)
  if exists(target) then fail('esiste già: ' .. path.make_relative(target, ROOT)) end
  local text = read_file(path.join { TEMPLATES, template })
  if edit then text = edit(text) end
  write_file(target, text)
  say('creato ' .. path.make_relative(target, ROOT))
end

local function build_report(file)
  require_data()
  local src = absolute(file)
  if not exists(src) then fail('file non trovato: ' .. file) end
  local stem = path.split_extension(path.filename(src))
  if not path.filename(src):match(REPORT_PATTERN) then
    say('Attenzione: ' .. path.filename(src) ..
      ' non ha un nome tipo 26-11-20.md (YY-MM-DD.md): non entrerà nel compendio.')
  end
  local out = path.join { OUTDIR, stem .. '.pdf' }
  say('→ report: ' .. path.make_relative(src, ROOT))
  run(PANDOC, { src, '--defaults=' .. path.join { ROOT, 'pandoc-defaults-report.yaml' }, '-o', out })
  say('  creato ' .. path.make_relative(out, ROOT))
end

local function build_compendium()
  require_data()
  require_file(COVER, 'crealo con `pandoc lua scripts/unibs.lua cover` (task "UNIBS: nuova copertina compendio")')
  say('→ compendio')
  run(PANDOC, { '--defaults=' .. path.join { ROOT, 'pandoc-defaults-compendium.yaml' } })
  say('  creato ' .. path.make_relative(path.join { OUTDIR, 'compendio.pdf' }, ROOT))
end

local commands = {}

function commands.report(args)
  if #args == 0 then
    local files = report_files()
    if #files == 0 then fail('nessun report YY-MM-DD.md in weekly-reports/') end
    args = { path.join { REPORTS, files[#files] } }
  end
  for _, f in ipairs(args) do build_report(f) end
end

function commands.compendium() build_compendium() end

function commands.all()
  for _, name in ipairs(report_files()) do build_report(path.join { REPORTS, name }) end
  build_compendium()
end

function commands.new(args)
  local stamp = (args[1] and args[1] ~= '') and args[1] or os.date('%y-%m-%d')
  local yy, mm, dd = stamp:match('^(%d%d)%-(%d%d)%-(%d%d)$')
  if not yy then fail('data non valida "' .. stamp .. '": usa il formato YY-MM-DD') end
  from_template('YY-MM-DD.md', path.join { REPORTS, stamp .. '.md' }, function(text)
    return (text:gsub('«AAAA%-MM%-GG»', string.format('20%s-%s-%s', yy, mm, dd), 1))
  end)
end

function commands.cover()
  from_template('cover_template.md', COVER)
end

function commands.assets()
  for _, name in ipairs(system.list_directory(path.join { ROOT, 'res' })) do
    local stem, ext = path.split_extension(name)
    if ext == '.svg' then
      local src, out = path.join { 'res', name }, path.join { 'res', stem .. '.pdf' }
      run('rsvg-convert', { '-f', 'pdf', '-o', out, src })
      say('creato ' .. out)
    end
  end
end

function commands.help()
  local doc = read_file(absolute(arg[0])):match('%-%-%[%[(.-)%]%]')
  say(doc)
end

-- main
system.make_directory(OUTDIR, true)
local cmd = arg[1] or 'help'
local rest = {}
for i = 2, #arg do rest[#rest + 1] = arg[i] end
if not commands[cmd] then fail('comando sconosciuto "' .. cmd .. '" (vedi: pandoc lua scripts/unibs.lua help)') end
commands[cmd](rest)
