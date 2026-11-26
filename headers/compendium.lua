--[[
compendium.lua -- pandoc filter for the compendium.

Input document: cover.md (its body, if any, is an optional preface).
Body produced:
  data macros | compendium cover | personal-info block | table of contents
  | preface | for each weekly-reports/YY-MM-DD.md, in chronological order:
  weekly cover + report body
Each report is parsed with pandoc.read; its identifiers are prefixed to keep
them unique across reports. Referenced by pandoc-defaults-compendium.yaml.
]]

local path = pandoc.path
local C = dofile(path.join { path.directory(PANDOC_SCRIPT_FILE), 'unibs-common.lua' })

local REPORTS_DIR = path.join { C.root, 'weekly-reports' }

--- Report files sorted chronologically (the YY-MM-DD name is the sort key).
local function report_files()
  local files = pandoc.List()
  for _, name in ipairs(pandoc.system.list_directory(REPORTS_DIR)) do
    if name:match(C.REPORT_PATTERN) then files:insert(name) end
  end
  table.sort(files)
  return files
end

local function read_file(p)
  local fh = assert(io.open(p, 'rb'))
  local text = fh:read('a')
  fh:close()
  return text
end

--- Prefix identifiers and internal links so that reports do not clash.
local function prefix_ids(blocks, prefix)
  local function fix(el)
    if el.identifier and el.identifier ~= '' then
      el.identifier = prefix .. el.identifier
    end
    return el
  end
  return blocks:walk {
    Header = fix, Div = fix, Span = fix, CodeBlock = fix, Code = fix,
    Figure = fix, Table = fix, Image = fix,
    Link = function(link)
      fix(link)
      if link.target:sub(1, 1) == '#' then
        link.target = '#' .. prefix .. link.target:sub(2)
      end
      return link
    end,
  }
end

local function build(doc)
  local meta = doc.meta
  C.warn_placeholders(meta, 'cover.md + DATA.yaml')
  C.set_author(meta)

  local blocks = pandoc.Blocks {
    C.data_block(meta),
    C.compendium_cover(meta),
    C.info_block(meta),
    pandoc.RawBlock('latex', '\\tableofcontents'),
  }
  blocks:extend(doc.blocks) -- optional preface from cover.md

  local files = report_files()
  if #files == 0 then
    C.warn('nessun report trovato in weekly-reports/ (nomi attesi: YY-MM-DD.md)')
  end
  for _, name in ipairs(files) do
    local yy, mm, dd = name:match(C.REPORT_PATTERN)
    local report = pandoc.read(read_file(path.join { REPORTS_DIR, name }), 'markdown')
    C.warn_placeholders(report.meta, name)
    blocks:insert(C.weekly_cover(report.meta, string.format('20%s-%s-%s', yy, mm, dd)))
    -- No divider line on a section opening the page right after the cover.
    local first = report.blocks[1]
    if first and first.t == 'Header' and first.level == 1 then
      blocks:insert(pandoc.RawBlock('latex', '\\unibsNoSectionLine'))
    end
    blocks:extend(prefix_ids(report.blocks, string.format('r%s%s%s-', yy, mm, dd)))
  end
  io.stderr:write(string.format('[unibs] compendio: %d report inclusi\n', #files))
  return pandoc.Pandoc(blocks, meta)
end

return {
  { Pandoc = build },
  C.style,
}
