-- c4ffein.lua -- colorscheme


-- Shouldn't set there actually, but ensure we have termguicolors set
vim.opt.termguicolors = true


-- Define colors
local colors = {
  fg              = "#F8F8F2",
  selection       = "#44475A",
  comment         = "#777777",
  red             = "#FF5555",
  orange          = "#FFCCAA",
  yellow          = "#F1FA8C",
  green           = "#88FFAA",
  purple          = "#BD93F9",
  cyan            = "#88EEFF",
  pink            = "#FF79C6",
  bright_red      = "#FF6E6E",
  bright_green    = "#69FF94",
  bright_yellow   = "#FFFFA5",
  bright_blue     = "#BB88FF",
  bright_magenta  = "#FF92DF",
  bright_cyan     = "#A4FFFF",
  bright_white    = "#FFFFFF",
  menu            = "#21222C",
  visual          = "#555555",
  gutter_fg       = "#4B5263",
  nontext         = "#3B4048",
  white           = "#FFFFFF",
  black           = "#191A21",
}


-- Clear existing highlights
vim.cmd('highlight clear')
if vim.g.syntax_on ~= nil then
  vim.cmd('syntax reset')
end


-- Set colorscheme name
vim.g.colors_name = 'c4ffein'


-- Define highlight groups
local highlights = {

  -- Editor highlights
  Normal            = { fg = colors.fg, bg = colors.bg                  },
  NormalFloat       = { fg = colors.fg, bg = colors.bg                  },
  ColorColumn       = { bg = colors.selection                           },
  Cursor            = { reverse = true                                  },
  CursorLine        = { bg = colors.selection                           },
  CursorColumn      = { bg = colors.black                               },
  LineNr            = { fg = colors.visual                              },
  CursorLineNr      = { fg = colors.fg, bold = true                     },
  VertSplit         = { fg = colors.black                               },

  -- Syntax highlighting
  Comment           = { fg = colors.comment                             },
  String            = { fg = colors.green                               },
  Number            = { fg = colors.orange                              },
  Float             = { fg = colors.orange                              },
  Boolean           = { fg = colors.cyan                                },
  Constant          = { fg = colors.yellow                              },
  Character         = { fg = colors.yellow                              },
  FloatBorder       = { fg = colors.white                               },
  Function          = { fg = colors.cyan                                },
  Label             = { fg = colors.cyan                                },
  Exception         = { fg = colors.purple                              },
  PreProc           = { fg = colors.yellow                              },
  Include           = { fg = colors.purple                              },
  Define            = { fg = colors.purple                              },
  Title             = { fg = colors.cyan                                },
  Macro             = { fg = colors.purple                              },
  PreCondit         = { fg = colors.cyan                                },
  StorageClass      = { fg = colors.pink                                },
  Structure         = { fg = colors.yellow                              },
  TypeDef           = { fg = colors.yellow                              },
  SpecialComment    = { fg = colors.comment, italic = true              },
  Underlined        = { fg = colors.cyan, underline = true              },
  Keyword           = { fg = colors.cyan                                },
  Keywords          = { fg = colors.cyan                                },
  Identifier        = { fg = colors.cyan                                },
  Statement         = { fg = colors.bright_magenta                      },
  Conditional       = { fg = colors.pink                                },
  Repeat            = { fg = colors.pink                                },
  Operator          = { fg = colors.bright_magenta                      },
  Type              = { fg = colors.cyan                                },
  Special           = { fg = colors.green, italic = true                },
  Error             = { fg = colors.bright_red                          },
  Todo              = { fg = colors.purple, bold = true, italic = true  },

  -- Other
  Conceal           = { fg = colors.comment },

  StatusLine        = { fg = colors.white, bg = colors.black            },
  StatusLineNC      = { fg = colors.comment                             },
  StatusLineTerm    = { fg = colors.white, bg = colors.black            },
  StatusLineTermNC  = { fg = colors.comment                             },

  Directory         = { fg = colors.cyan                                },
  DiffAdd           = { fg = colors.bg, bg = colors.green               },
  DiffChange        = { fg = colors.orange                              },
  DiffDelete        = { fg = colors.red                                 },
  DiffText          = { fg = colors.comment                             },

  ErrorMsg          = { fg = colors.bright_red                          },
  WinSeparator      = { fg = colors.black                               },
  Folded            = { fg = colors.comment                             },
  FoldColumn        = {                                                 },
  Search            = { fg = colors.black, bg = colors.orange           },
  IncSearch         = { fg = colors.orange, bg = colors.comment         },
  EndOfBuffer       = { fg = colors.visual                              },
  MatchParen        = { fg = colors.fg, underline = true                },
  NonText           = { fg = colors.nontext                             },
  Pmenu             = { fg = colors.white, bg = colors.menu             },
  PmenuSel          = { fg = colors.white, bg = colors.selection        },
  PmenuSbar         = { bg = colors.bg                                  },
  PmenuThumb        = { bg = colors.selection                           },

  Question          = { fg = colors.purple                              },
  QuickFixLine      = { fg = colors.black, bg = colors.yellow           },
  SpecialKey        = { fg = colors.nontext                             },

  SpellBad          = { fg = colors.bright_red, underline = true        },
  SpellCap          = { fg = colors.yellow                              },
  SpellLocal        = { fg = colors.yellow                              },
  SpellRare         = { fg = colors.yellow                              },

  TabLine           = { fg = colors.comment                             },
  TabLineSel        = { fg = colors.white                               },
  TabLineFill       = { bg = colors.bg                                  },
  Terminal          = { fg = colors.white, bg = colors.black            },
  Visual            = { bg = colors.visual                              },
  VisualNOS         = { fg = colors.visual                              },
  WarningMsg        = { fg = colors.yellow                              },
  WildMenu          = { fg = colors.black, bg = colors.white            },

}


-- Set highlights
local function set_highlights()
  for group, settings in pairs(highlights) do
    vim.api.nvim_set_hl(0, group, settings)
  end
end
set_highlights()


-- Return the color palette
return colors
