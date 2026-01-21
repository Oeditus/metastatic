{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import GHC.Generics
import Language.Haskell.Exts
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

-- | Response wrapper for JSON output
data Response = Response
  { status :: String,
    ast :: Maybe Aeson.Value,
    errorMessage :: Maybe String
  }
  deriving (Generic, Show)

instance Aeson.ToJSON Response where
  toJSON = Aeson.genericToJSON Aeson.defaultOptions

-- | Parse Haskell source and output JSON AST
main :: IO ()
main = do
  source <- TIO.getContents
  case parseExp (T.unpack source) of
    ParseOk parsedExpr -> do
      let astJson = exprToJson parsedExpr
      BL.putStrLn $
        Aeson.encode $
          Response
            { status = "ok",
              ast = Just astJson,
              errorMessage = Nothing
            }
    ParseFailed loc err -> do
      hPutStrLn stderr $ "Parse error at " ++ show loc ++ ": " ++ err
      BL.putStrLn $
        Aeson.encode $
          Response
            { status = "error",
              ast = Nothing,
              errorMessage = Just $ "Parse error: " ++ err
            }
      exitFailure

-- | Convert Haskell expression to JSON
exprToJson :: Exp SrcSpanInfo -> Aeson.Value
exprToJson expr = case expr of
  -- Literals
  Lit _ lit -> Aeson.object
    [ "type" Aeson..= ("literal" :: String)
    , "value" Aeson..= literalToJson lit
    ]
  
  -- Variables
  Var _ qname -> Aeson.object
    [ "type" Aeson..= ("var" :: String)
    , "name" Aeson..= qnameToString qname
    ]
  
  -- Constructor
  Con _ qname -> Aeson.object
    [ "type" Aeson..= ("con" :: String)
    , "name" Aeson..= qnameToString qname
    ]
  
  -- Application (function call)
  App _ func arg -> Aeson.object
    [ "type" Aeson..= ("app" :: String)
    , "function" Aeson..= exprToJson func
    , "argument" Aeson..= exprToJson arg
    ]
  
  -- Infix application (operators)
  InfixApp _ left op right -> Aeson.object
    [ "type" Aeson..= ("infix" :: String)
    , "left" Aeson..= exprToJson left
    , "operator" Aeson..= qopToString op
    , "right" Aeson..= exprToJson right
    ]
  
  -- Lambda
  Lambda _ pats body -> Aeson.object
    [ "type" Aeson..= ("lambda" :: String)
    , "patterns" Aeson..= map patToJson pats
    , "body" Aeson..= exprToJson body
    ]
  
  -- Let binding
  Let _ binds body -> Aeson.object
    [ "type" Aeson..= ("let" :: String)
    , "bindings" Aeson..= bindsToJson binds
    , "body" Aeson..= exprToJson body
    ]
  
  -- If-then-else
  If _ cond thenExp elseExp -> Aeson.object
    [ "type" Aeson..= ("if" :: String)
    , "condition" Aeson..= exprToJson cond
    , "then" Aeson..= exprToJson thenExp
    , "else" Aeson..= exprToJson elseExp
    ]
  
  -- Case expression
  Case _ scrut alts -> Aeson.object
    [ "type" Aeson..= ("case" :: String)
    , "scrutinee" Aeson..= exprToJson scrut
    , "alternatives" Aeson..= map altToJson alts
    ]
  
  -- List
  List _ exprs -> Aeson.object
    [ "type" Aeson..= ("list" :: String)
    , "elements" Aeson..= map exprToJson exprs
    ]
  
  -- Tuple
  Tuple _ Boxed exprs -> Aeson.object
    [ "type" Aeson..= ("tuple" :: String)
    , "elements" Aeson..= map exprToJson exprs
    ]
  
  -- Parenthesized expression
  Paren _ expr' -> exprToJson expr'
  
  -- List comprehension
  ListComp _ expr quals -> Aeson.object
    [ "type" Aeson..= ("list_comp" :: String)
    , "expression" Aeson..= exprToJson expr
    , "qualifiers" Aeson..= map qualStmtToJson quals
    ]
  
  -- Do notation
  Do _ stmts -> Aeson.object
    [ "type" Aeson..= ("do" :: String)
    , "statements" Aeson..= map stmtToJson stmts
    ]
  
  -- Fallback for unsupported constructs
  _ -> Aeson.object
    [ "type" Aeson..= ("unsupported" :: String)
    , "original" Aeson..= show expr
    ]

-- | Convert literal to JSON
literalToJson :: Literal SrcSpanInfo -> Aeson.Value
literalToJson lit = case lit of
  Int _ i _ -> Aeson.object
    [ "literalType" Aeson..= ("int" :: String)
    , "value" Aeson..= i
    ]
  Frac _ r _ -> Aeson.object
    [ "literalType" Aeson..= ("float" :: String)
    , "value" Aeson..= (fromRational r :: Double)
    ]
  Char _ c _ -> Aeson.object
    [ "literalType" Aeson..= ("char" :: String)
    , "value" Aeson..= [c]
    ]
  String _ s _ -> Aeson.object
    [ "literalType" Aeson..= ("string" :: String)
    , "value" Aeson..= s
    ]
  _ -> Aeson.object
    [ "literalType" Aeson..= ("other" :: String)
    , "value" Aeson..= show lit
    ]

-- | Convert qualified name to string
qnameToString :: QName l -> String
qnameToString (Qual _ (ModuleName _ m) (Ident _ n)) = m ++ "." ++ n
qnameToString (Qual _ (ModuleName _ m) (Symbol _ s)) = m ++ "." ++ s
qnameToString (UnQual _ (Ident _ n)) = n
qnameToString (UnQual _ (Symbol _ s)) = s
qnameToString (Special _ (UnitCon _)) = "()"
qnameToString (Special _ (ListCon _)) = "[]"
qnameToString (Special _ (TupleCon _ Boxed n)) = replicate (n - 1) ',' 
qnameToString _ = "unknown"

-- | Convert qualified operator to string
qopToString :: QOp l -> String
qopToString (QVarOp _ qname) = qnameToString qname
qopToString (QConOp _ qname) = qnameToString qname

-- | Convert pattern to JSON
patToJson :: Pat SrcSpanInfo -> Aeson.Value
patToJson pat = case pat of
  PVar _ (Ident _ n) -> Aeson.object
    [ "type" Aeson..= ("var_pat" :: String)
    , "name" Aeson..= n
    ]
  PLit _ _ lit -> Aeson.object
    [ "type" Aeson..= ("lit_pat" :: String)
    , "literal" Aeson..= literalToJson lit
    ]
  PWildCard _ -> Aeson.object
    [ "type" Aeson..= ("wildcard" :: String)
    ]
  _ -> Aeson.object
    [ "type" Aeson..= ("unsupported_pat" :: String)
    , "original" Aeson..= show pat
    ]

-- | Convert bindings to JSON
bindsToJson :: Binds SrcSpanInfo -> Aeson.Value
bindsToJson (BDecls _ decls) = Aeson.toJSON $ map declToJson decls
bindsToJson _ = Aeson.Null

-- | Convert declaration to JSON
declToJson :: Decl SrcSpanInfo -> Aeson.Value
declToJson decl = case decl of
  PatBind _ pat rhs _ -> Aeson.object
    [ "type" Aeson..= ("pat_bind" :: String)
    , "pattern" Aeson..= patToJson pat
    , "rhs" Aeson..= rhsToJson rhs
    ]
  _ -> Aeson.object
    [ "type" Aeson..= ("unsupported_decl" :: String)
    ]

-- | Convert right-hand side to JSON
rhsToJson :: Rhs SrcSpanInfo -> Aeson.Value
rhsToJson (UnGuardedRhs _ expr) = exprToJson expr
rhsToJson _ = Aeson.Null

-- | Convert case alternative to JSON
altToJson :: Alt SrcSpanInfo -> Aeson.Value
altToJson (Alt _ pat rhs _) = Aeson.object
  [ "pattern" Aeson..= patToJson pat
  , "rhs" Aeson..= rhsToJson rhs
  ]

-- | Convert qualifier statement to JSON
qualStmtToJson :: QualStmt SrcSpanInfo -> Aeson.Value
qualStmtToJson (QualStmt _ stmt) = stmtToJson stmt
qualStmtToJson _ = Aeson.Null

-- | Convert statement to JSON
stmtToJson :: Stmt SrcSpanInfo -> Aeson.Value
stmtToJson stmt = case stmt of
  Generator _ pat expr -> Aeson.object
    [ "type" Aeson..= ("generator" :: String)
    , "pattern" Aeson..= patToJson pat
    , "expression" Aeson..= exprToJson expr
    ]
  Qualifier _ expr -> Aeson.object
    [ "type" Aeson..= ("qualifier" :: String)
    , "expression" Aeson..= exprToJson expr
    ]
  LetStmt _ binds -> Aeson.object
    [ "type" Aeson..= ("let_stmt" :: String)
    , "bindings" Aeson..= bindsToJson binds
    ]
  _ -> Aeson.object
    [ "type" Aeson..= ("unsupported_stmt" :: String)
    ]
