{-# LANGUAGE OverloadedStrings #-}
{- |
   Module      : Text.Pandoc.Readers.Docx.Fields
   Copyright   : Copyright (C) 2014-2020 Jesse Rosenthal
   License     : GNU GPL, version 2 or above

   Maintainer  : Jesse Rosenthal <jrosenthal@jhu.edu>
   Stability   : alpha
   Portability : portable

For parsing Field definitions in instText tags, as described in
ECMA-376-1:2016, §17.16.5 -}

module Text.Pandoc.Readers.Docx.Fields ( FieldInfo(..)
                                       , parseFieldInfo
                                       ) where

import Data.Functor (($>), void)
import qualified Data.Text as T
import Text.Pandoc.Parsing

type URL = T.Text
type Anchor = T.Text

data FieldInfo = HyperlinkField URL
                -- The boolean indicates whether the field is a hyperlink.
               | PagerefField Anchor Bool
               | IndexrefField T.Text (Maybe T.Text) -- second is optional 'see'
               | CslCitation T.Text
               | CslBibliography
               | EndNoteCite T.Text
               | EndNoteRefList
               | UnknownField
               deriving (Show)

type Parser = Parsec T.Text ()

parseFieldInfo :: T.Text -> Either ParseError FieldInfo
parseFieldInfo = parse fieldInfo ""

fieldInfo :: Parser FieldInfo
fieldInfo = do
  spaces
  (HyperlinkField <$> hyperlink)
    <|>
    ((uncurry PagerefField) <$> pageref)
    <|>
    ((uncurry IndexrefField) <$> indexref)
    <|>
    addIn
    <|>
    return UnknownField

addIn :: Parser FieldInfo
addIn = do
  string "ADDIN"
  spaces
  try cslCitation <|> cslBibliography <|> endnoteCite <|> endnoteRefList

cslCitation :: Parser FieldInfo
cslCitation = do
  optional (string "ZOTERO_ITEM" *> spaces)
  string "CSL_CITATION"
  spaces
  CslCitation <$> getInput

cslBibliography :: Parser FieldInfo
cslBibliography = do
  string "ZOTERO_BIBL" <|> string "Mendeley Bibliography CSL_BIBLIOGRAPHY"
  return CslBibliography

endnoteCite :: Parser FieldInfo
endnoteCite = try $ do
  string "EN.CITE"
  spaces
  EndNoteCite <$> getInput

endnoteRefList :: Parser FieldInfo
endnoteRefList = try $ do
  string "EN.REFLIST"
  return EndNoteRefList


escapedQuote :: Parser T.Text
escapedQuote = string "\\\"" $> "\\\""

inQuotes :: Parser T.Text
inQuotes =
  try escapedQuote <|> (T.singleton <$> anyChar)

quotedString :: Parser T.Text
quotedString = do
  char '"'
  T.concat <$> manyTill inQuotes (try (char '"'))

unquotedString :: Parser T.Text
unquotedString = T.pack <$> manyTill anyChar (try $ void (lookAhead space) <|> eof)

fieldArgument :: Parser T.Text
fieldArgument = do
  notFollowedBy (char '\\') -- switch
  quotedString <|> unquotedString

hyperlink :: Parser URL
hyperlink = do
  string "HYPERLINK"
  spaces
  farg <- option "" $ notFollowedBy (char '\\') *> fieldArgument
  switches <- many fieldSwitch
  let url = case [s | ('l',s) <- switches] of
              [s] -> farg <> "#" <> s
              _   -> farg
  return url

-- See §17.16.5.45
fieldSwitch :: Parser (Char, T.Text)
fieldSwitch = try $ do
  spaces
  char '\\'
  c <- anyChar
  spaces
  farg <- fieldArgument
  return (c, farg)

pageref :: Parser (Anchor, Bool)
pageref = do
  string "PAGEREF"
  spaces
  farg <- fieldArgument
  switches <- many fieldSwitch
  let isLink = any ((== 'h') . fst) switches
  return (farg, isLink)

-- second element of tuple is optional "see".
indexref :: Parser (T.Text, Maybe T.Text)
indexref = do
  string "XE"
  spaces
  farg <- fieldArgument
  switches <- spaces *> many fieldSwitch
  case [see | ('t', see) <- switches] of
     [see] -> pure (farg, Just see)
     _     -> pure (farg, Nothing)
