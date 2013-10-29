--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Paper
  ( Paper (..)
  , Entry
  , parseEntry
  , getField
  , getField'
  , paperID
  , paperURI
  ) where

--------------------------------------------------------------------------------
import            Control.Applicative (empty, (<$>), (<*>))
import            Control.Monad (liftM)
import            Control.Monad.Error
import            Data.Binary
import            Data.List.HT
import            Data.Maybe
import            Data.Typeable
import            Hakyll
import            Network.URI
import qualified  Text.BibTeX.Entry   as BibTex
import qualified  Text.BibTeX.Format  as BibTex.Format
import qualified  Text.BibTeX.Parse   as BibTex.Parse
import qualified  Text.Parsec         as Parsec           
import            Text.Pandoc         ( 
  Pandoc (..), Block( Para, Plain ), HTMLMathMethod ( MathJax ), 
  def,
  readLaTeX, writerHTMLMathMethod, writeHtmlString
  )
--------------------------------------------------------------------------------
newtype Entry = Entry BibTex.T
  deriving (Show, Typeable, Writable, Binary)

data Paper = Paper { entry :: BibTex.T, conference :: BibTex.T }
  deriving (Show, Typeable)

instance Writable BibTex.T where
  write fp item =
    writeFile fp $ BibTex.Format.entry . itemBody $ item

instance Binary BibTex.T where
  put t = do
    put $ BibTex.entryType t
    put $ BibTex.identifier t
    put $ BibTex.fields t

  get = BibTex.Cons <$> get <*> get <*> get

instance Binary Paper where
  put (Paper entry conf) = do
    put $ entry
    put $ conf

  get = Paper <$> get <*> get

instance Writable Paper where
  write fp item =
    let Paper entry conf = itemBody item
    in writeFile fp ((BibTex.Format.entry entry) ++ (BibTex.Format.entry conf))

instance Eq Paper where
  (==) paper paper' = paperID paper == paperID paper'

instance Ord Paper where
  compare paper paper' = compare (paperID paper) (paperID paper')

parseEntry :: FilePath -> Entry
parseEntry path =
  case Parsec.parse BibTex.Parse.file "<BibTeX entry>" path of
    Left err       -> error $ show err
    Right [entry]  -> Entry entry 
    Right []       -> error $ "Empty BibTeX file: " ++ path
    Right _        -> error "BibTeX files must only have a single entry"

--------------------------------------------------------------------------------
-- Get the paper's indentifier
paperID :: Paper -> Identifier
paperID (Paper entry _) = fromFilePath $ BibTex.identifier entry

paperURI :: Paper -> Identifier
paperURI paper = fromFilePath ("paper/" ++ (toFilePath $ paperID paper) ++ ".html") 

--------------------------------------------------------------------------------
-- Converts a TeX string into HTML + MathJax
-- (Adapted from Jasper Van der Jeugt's Hakyll-BibTeX code)
latexToHtml tex =
  let p = case readLaTeX def tex of
        Pandoc meta [Para para] -> Pandoc meta [Plain para]
        x                       -> x
  in writeHtmlString 
    def { writerHTMLMathMethod = MathJax "" } p

--------------------------------------------------------------------------------
getField :: String -> (Item Entry) -> Maybe String
getField key = getField' key . itemBody

getField' :: String -> Entry -> Maybe String
getField' key entry@(Entry t) =
  case key of
  "identifier"  -> Just $ BibTex.identifier t
  "firstpage"   -> firstpage
  "lastpage"    -> lastpage
  "url"         -> fmap (toURI "html") $ identifier
  "pdf"         -> fmap (toURI "pdf") $ identifier
  "rawtitle"    -> lookup "title" . BibTex.fields $ t
  _             -> fmap latexToHtml (lookup key . BibTex.fields $ t)
  where
    pages = getField' "pages" entry
    identifier = getField' "identifier" entry
    firstpage = fmap (takeWhile isNumber) pages
    lastpage  = fmap (reverse . takeWhile isNumber . reverse) pages
    isNumber c = c `elem` ['0'..'9'] ++ ['x','v','i']

toURI :: String -> FilePath -> String
toURI ext path = (escapeURIString isUnreserved path) ++ "." ++ ext