--[[
report.lua -- pandoc filter for a single weekly report.

Body produced:  data macros (DATA.yaml) | weekly cover | personal-info block | report body
Referenced by pandoc-defaults-report.yaml.
]]

local C = dofile(pandoc.path.join { pandoc.path.directory(PANDOC_SCRIPT_FILE), 'unibs-common.lua' })

local function build(doc)
  local meta = doc.meta
  local source = PANDOC_STATE.input_files[1] or 'report'
  C.warn_placeholders(meta, pandoc.path.filename(source) .. ' + DATA.yaml')
  C.set_author(meta)

  -- Fallback date from the file name (YY-MM-DD.md).
  local fallback
  local yy, mm, dd = pandoc.path.filename(source):match(C.REPORT_PATTERN)
  if yy then fallback = string.format('20%s-%s-%s', yy, mm, dd) end

  local blocks = pandoc.Blocks {
    C.data_block(meta),
    C.weekly_cover(meta, fallback),
    C.info_block(meta),
  }
  blocks:extend(doc.blocks)
  return pandoc.Pandoc(blocks, meta)
end

return {
  { Pandoc = build },
  C.style,
}
