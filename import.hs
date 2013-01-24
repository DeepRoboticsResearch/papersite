--------------------------------------------------------------------------------
{-# LANGUAGE DeriveDataTypeable #-}

--------------------------------------------------------------------------------
import            Control.Applicative
import            Control.Monad
import            Data.Char
import            Data.Functor
import            Data.List
import            Data.Maybe
import            System.Directory
import            System.Environment
import            System.IO
import qualified  Text.BibTeX.Entry    as BibTex
import qualified  Text.BibTeX.Format   as BibTex
import qualified  Text.BibTeX.Parse    as BibTex.Parse
import qualified  Text.LaTeX.Character as LaTeX
import qualified  Text.Parsec          as Parsec

--------------------------------------------------------------------------------
data Proceedings = 
  Proceedings { conference :: BibTex.T, entries :: [BibTex.T] }
  deriving (Show)

instance Eq BibTex.T where
  (==) t t' = (BibTex.entryType t) == (BibTex.entryType t')

fieldMap :: (String -> String) -> BibTex.T -> BibTex.T
fieldMap f t = 
  BibTex.Cons 
    (BibTex.entryType t) 
    (BibTex.identifier t)
    (map (\(k,v) -> (k,f v)) $ BibTex.fields t)

fieldFilter :: (String -> Bool) -> BibTex.T -> BibTex.T
fieldFilter p t =
  BibTex.Cons
    (BibTex.entryType t)
    (BibTex.identifier t)
    (filter (p.fst) (BibTex.fields t))

value :: String -> BibTex.T -> String
value key entry = fromJust $ lookup key $ BibTex.fields entry

year :: Proceedings -> String
year = value "year" . conference

shortname :: Proceedings -> String
shortname = value "shortname" . conference


--------------------------------------------------------------------------------
-- | Imports a single BibTeX file into the given directory. The
--   BibTeX file must contain:
--
--    * One or more @\@InProceedings@ entries. These must contain the following
--      fields: title, author, abstract, and pages
--    
--    * Exactly one @\@Proceedings@ or @\@Conference@ entries. This must
--      contain the following fields: shortname, booktitle, year, editor, and volume
--   
--   The importer converts the entries in the BibTeX file to a number of
--   files in the @db/@ directory. It does so as follows:
--
--   1. The \@Proceedings / \@Conference entry (henceforth, "conference")
--      is saved to a file @db/conf/N/Y.bib@ where @N@ is the value
--      of the @shortname@ field in the conference entry and @Y@ is the
--      value of the @year@ field.
--
--      If the @booktitle@ field is not present it is set to the value of
--      the @title@ field.
--
--   2. A modified version of each other entry (the @\@InProceedings@ entries) 
--      is written to @db/conf/N/Y/ID.bib@ where @N@ and @Y@ are as above 
--      and @ID@ is value of the entry's BibTeX indentifier.
--
--      The modifications to the entry are as follows:
--
--      a. The @crossref@ field is set to @N/Y@ where @N@ and @Y@ are as above.
--   
--   3. For every author appear in the @author@ field of a non-conference entry
--      a file is written to @db/authors/A.bib@ where @A@ is a unique
--      identifier for the author (described below) and the contents of the
--      file are of the form:
--      @
--        @author{A,
--          lastname = { Smith },
--          firstnames = { John Xavier }
--        }
--      @
--
--      This file is only written to if it does not already exist.
--
--      The identifer @A@ is of the form @Lastname_IJ@ where @Lastname@
--      is a unicode-cleansed version of the author's last name and @I@ and
--      @J@ are the unicode-cleansed initials of the author's first names.
main :: IO()
main = do
  args <- getArgs 
  case args of
    [name, dbPath]  -> do
      print $ "Importing " ++ name ++ " to " ++ dbPath
      handle  <- openFile name ReadMode
      bibtex  <- hGetContents handle

      let parsed = parseBibFile bibtex
      case parsed of
        (Just procs)  ->  do
          let dir = intercalate "/" [dbPath, shortname procs, year procs ]
          createDirectoryIfMissing True dir
          writeProceedings procs dir 
          forM_ (entries procs) $ \entry -> writeEntry entry dir
        Nothing             -> error $ "Could not parse " ++ name


    _            -> print "Usage: import bibtex database_directory"

parseBibFile :: String -> Maybe Proceedings
parseBibFile string = case Parsec.parse BibTex.Parse.file "<bib file>" string of
  Left err -> error $ show err
  Right xs -> makeProceedings xs

makeProceedings :: [BibTex.T] -> Maybe Proceedings
makeProceedings entries =
  liftM2 Proceedings conference entries'
  where
    conference = find isConference entries
    entries'   = liftM2 delete conference (Just entries)

isConference :: BibTex.T -> Bool
isConference entry =
  map toLower (BibTex.entryType entry) `elem` ["conference", "proceedings"]

writeProceedings :: Proceedings -> FilePath -> IO ()
writeProceedings procs dirPath = do
  let conf = conference procs
  procHandle <- openFile (dirPath ++ ".bib") WriteMode
  hPutStr procHandle $ BibTex.entry $ fieldMap LaTeX.fromUnicodeString $ conf
  hClose procHandle

writeEntry :: BibTex.T -> FilePath -> IO ()
writeEntry entry dirPath = do
  let entryID = BibTex.identifier entry
  handle <- openFile (dirPath ++ "/" ++ entryID ++ ".bib") WriteMode
  hPutStr handle $ BibTex.entry $ cleanEntry entry

cleanEntry = fieldFilter (`elem` ["author", "title", "abstract", "pages"])
