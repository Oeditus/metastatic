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
import System.Environment (getArgs)

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
  args <- getArgs
  source <- case args of
    (path:_) -> TIO.readFile path
    []       -> TIO.getContents
  let sourceStr = T.unpack source
  -- Try parsing as module first, then as declaration, then as expression
  case parseModule sourceStr of
    ParseOk parsedModule -> do
      let astJson = moduleToJson parsedModule
      BL.putStrLn $
        Aeson.encode $
          Response
            { status = "ok",
              ast = Just astJson,
              errorMessage = Nothing
            }
    ParseFailed _ _ -> case parseDecl sourceStr of
      ParseOk parsedDecl -> do
        let astJson = declToJsonFull parsedDecl
        BL.putStrLn $
          Aeson.encode $
            Response
              { status = "ok",
                ast = Just astJson,
                errorMessage = Nothing
              }
      ParseFailed _ _ -> case parseExp sourceStr of
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

-- | Convert SrcSpanInfo to a JSON location object
srcSpanToJson :: SrcSpanInfo -> Aeson.Value
srcSpanToJson (SrcSpanInfo (SrcSpan _ sl sc el ec) _) = Aeson.object
  [ "startLine" Aeson..= sl
  , "startCol" Aeson..= sc
  , "endLine" Aeson..= el
  , "endCol" Aeson..= ec
  ]

-- | Convert Haskell expression to JSON
exprToJson :: Exp SrcSpanInfo -> Aeson.Value
exprToJson expr = case expr of
  -- Literals
  Lit l lit -> Aeson.object
    [ "type" Aeson..= ("literal" :: String)
    , "value" Aeson..= literalToJson lit
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Variables
  Var l qname -> Aeson.object
    [ "type" Aeson..= ("var" :: String)
    , "name" Aeson..= qnameToString qname
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Constructor
  Con l qname -> Aeson.object
    [ "type" Aeson..= ("con" :: String)
    , "name" Aeson..= qnameToString qname
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Application (function call)
  App l func arg -> Aeson.object
    [ "type" Aeson..= ("app" :: String)
    , "function" Aeson..= exprToJson func
    , "argument" Aeson..= exprToJson arg
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Infix application (operators)
  InfixApp l left op right -> Aeson.object
    [ "type" Aeson..= ("infix" :: String)
    , "left" Aeson..= exprToJson left
    , "operator" Aeson..= qopToString op
    , "right" Aeson..= exprToJson right
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Lambda
  Lambda l pats body -> Aeson.object
    [ "type" Aeson..= ("lambda" :: String)
    , "patterns" Aeson..= map patToJson pats
    , "body" Aeson..= exprToJson body
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Let binding
  Let l binds body -> Aeson.object
    [ "type" Aeson..= ("let" :: String)
    , "bindings" Aeson..= bindsToJson binds
    , "body" Aeson..= exprToJson body
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- If-then-else
  If l cond thenExp elseExp -> Aeson.object
    [ "type" Aeson..= ("if" :: String)
    , "condition" Aeson..= exprToJson cond
    , "then" Aeson..= exprToJson thenExp
    , "else" Aeson..= exprToJson elseExp
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Case expression
  Case l scrut alts -> Aeson.object
    [ "type" Aeson..= ("case" :: String)
    , "scrutinee" Aeson..= exprToJson scrut
    , "alternatives" Aeson..= map altToJson alts
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- List
  List l exprs -> Aeson.object
    [ "type" Aeson..= ("list" :: String)
    , "elements" Aeson..= map exprToJson exprs
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Tuple
  Tuple l Boxed exprs -> Aeson.object
    [ "type" Aeson..= ("tuple" :: String)
    , "elements" Aeson..= map exprToJson exprs
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Parenthesized expression
  Paren _ expr' -> exprToJson expr'
  
  -- List comprehension
  ListComp l expr quals -> Aeson.object
    [ "type" Aeson..= ("list_comp" :: String)
    , "expression" Aeson..= exprToJson expr
    , "qualifiers" Aeson..= map qualStmtToJson quals
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Do notation
  Do l stmts -> Aeson.object
    [ "type" Aeson..= ("do" :: String)
    , "statements" Aeson..= map stmtToJson stmts
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Expression type signature: (e :: T)
  ExpTypeSig l expr' ty -> Aeson.object
    [ "type" Aeson..= ("expr_type_sig" :: String)
    , "expression" Aeson..= exprToJson expr'
    , "signature" Aeson..= typeToJson ty
    , "location" Aeson..= srcSpanToJson l
    ]

  -- Record construction: C { field = value, ... }
  RecConstr l qname fields -> Aeson.object
    [ "type" Aeson..= ("record_constr" :: String)
    , "name" Aeson..= qnameToString qname
    , "fields" Aeson..= map fieldUpdateToJson fields
    , "location" Aeson..= srcSpanToJson l
    ]

  -- Record update: e { field = value, ... }
  RecUpdate l expr' fields -> Aeson.object
    [ "type" Aeson..= ("record_update" :: String)
    , "expression" Aeson..= exprToJson expr'
    , "fields" Aeson..= map fieldUpdateToJson fields
    , "location" Aeson..= srcSpanToJson l
    ]

  -- Left operator section: (x +)
  LeftSection l expr' op -> Aeson.object
    [ "type" Aeson..= ("left_section" :: String)
    , "expression" Aeson..= exprToJson expr'
    , "operator" Aeson..= qopToString op
    , "location" Aeson..= srcSpanToJson l
    ]

  -- Right operator section: (+ x)
  RightSection l op expr' -> Aeson.object
    [ "type" Aeson..= ("right_section" :: String)
    , "operator" Aeson..= qopToString op
    , "expression" Aeson..= exprToJson expr'
    , "location" Aeson..= srcSpanToJson l
    ]

  -- Negation: -x
  NegApp l expr' -> Aeson.object
    [ "type" Aeson..= ("negate" :: String)
    , "expression" Aeson..= exprToJson expr'
    , "location" Aeson..= srcSpanToJson l
    ]

  -- Enum sequence: [a .. b], [a, b .. c]
  EnumFromTo l from to -> enumToJson l "enum_from_to" from (Just to)
  EnumFrom l from -> enumToJson l "enum_from" from Nothing
  EnumFromThenTo l from thenE to -> enumThenToJson l from thenE (Just to)
  EnumFromThen l from thenE -> enumThenToJson l from thenE Nothing

  -- Fallback for unsupported constructs
  _ -> Aeson.object
    [ "type" Aeson..= ("unsupported" :: String)
    , "original" Aeson..= show expr
    ]

-- | Convert an enum-from(-to) expression to JSON
enumToJson :: SrcSpanInfo -> String -> Exp SrcSpanInfo -> Maybe (Exp SrcSpanInfo) -> Aeson.Value
enumToJson l tag from mTo = Aeson.object $
  [ "type" Aeson..= tag
  , "from" Aeson..= exprToJson from
  ] ++ maybe [] (\t -> ["to" Aeson..= exprToJson t]) mTo ++
  [ "location" Aeson..= srcSpanToJson l ]

-- | Convert an enum-from-then(-to) expression to JSON
enumThenToJson :: SrcSpanInfo -> Exp SrcSpanInfo -> Exp SrcSpanInfo -> Maybe (Exp SrcSpanInfo) -> Aeson.Value
enumThenToJson l from thenE mTo = Aeson.object $
  [ "type" Aeson..= ("enum_from_then" :: String)
  , "from" Aeson..= exprToJson from
  , "then" Aeson..= exprToJson thenE
  ] ++ maybe [] (\t -> ["to" Aeson..= exprToJson t]) mTo ++
  [ "location" Aeson..= srcSpanToJson l ]

-- | Convert a record field update to JSON
fieldUpdateToJson :: FieldUpdate SrcSpanInfo -> Aeson.Value
fieldUpdateToJson (FieldUpdate l qname expr') = Aeson.object
  [ "name" Aeson..= qnameToString qname
  , "value" Aeson..= exprToJson expr'
  , "location" Aeson..= srcSpanToJson l
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
qnameToString (Special _ (Cons _)) = ":"
qnameToString (Special _ (ExprHole _)) = "_"
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
  -- Constructor pattern: Just x, Nothing
  PApp _ qname pats -> Aeson.object
    [ "type" Aeson..= ("con_pat" :: String)
    , "name" Aeson..= qnameToString qname
    , "patterns" Aeson..= map patToJson pats
    ]
  -- Parenthesized pattern: (x:xs) -- transparent, unwrap
  PParen _ pat' -> patToJson pat'
  -- Tuple pattern: (a, b)
  PTuple _ Boxed pats -> Aeson.object
    [ "type" Aeson..= ("tuple_pat" :: String)
    , "elements" Aeson..= map patToJson pats
    ]
  -- List pattern: [a, b]
  PList _ pats -> Aeson.object
    [ "type" Aeson..= ("list_pat" :: String)
    , "elements" Aeson..= map patToJson pats
    ]
  -- Infix constructor pattern: x : xs
  PInfixApp _ lhs qname rhs -> Aeson.object
    [ "type" Aeson..= ("infix_pat" :: String)
    , "left" Aeson..= patToJson lhs
    , "operator" Aeson..= qnameToString qname
    , "right" Aeson..= patToJson rhs
    ]
  -- As-pattern: name@pat
  PAsPat _ (Ident _ n) pat' -> Aeson.object
    [ "type" Aeson..= ("as_pat" :: String)
    , "name" Aeson..= n
    , "pattern" Aeson..= patToJson pat'
    ]
  -- Lazy pattern: ~pat
  PIrrPat _ pat' -> patToJson pat'
  -- Bang pattern: !pat
  PBangPat _ pat' -> patToJson pat'
  -- Record pattern: C { field = pat }
  PRec _ qname fields -> Aeson.object
    [ "type" Aeson..= ("record_pat" :: String)
    , "name" Aeson..= qnameToString qname
    , "fields" Aeson..= map patFieldToJson fields
    ]
  _ -> Aeson.object
    [ "type" Aeson..= ("unsupported_pat" :: String)
    , "original" Aeson..= show pat
    ]

-- | Convert a record pattern field to JSON
patFieldToJson :: PatField SrcSpanInfo -> Aeson.Value
patFieldToJson (PFieldPat _ qname pat') = Aeson.object
  [ "name" Aeson..= qnameToString qname
  , "pattern" Aeson..= patToJson pat'
  ]
patFieldToJson (PFieldPun _ qname) = Aeson.object
  [ "name" Aeson..= qnameToString qname
  , "pattern" Aeson..= Aeson.object [ "type" Aeson..= ("var_pat" :: String), "name" Aeson..= qnameToString qname ]
  ]
patFieldToJson (PFieldWildcard _) = Aeson.object
  [ "name" Aeson..= ("_" :: String)
  , "pattern" Aeson..= Aeson.object [ "type" Aeson..= ("wildcard" :: String) ]
  ]

-- | Convert bindings to JSON
bindsToJson :: Binds SrcSpanInfo -> Aeson.Value
bindsToJson (BDecls _ decls) = Aeson.toJSON $ map declToJson decls
bindsToJson _ = Aeson.Null

-- | Convert module to JSON
moduleToJson :: Module SrcSpanInfo -> Aeson.Value
moduleToJson (Module _ _ _ _ decls) = Aeson.object
  [ "type" Aeson..= ("module" :: String)
  , "declarations" Aeson..= map declToJsonFull decls
  ]
moduleToJson _ = Aeson.object
  [ "type" Aeson..= ("unsupported_module" :: String)
  ]

-- | Convert declaration to JSON (full version with type signatures)
declToJsonFull :: Decl SrcSpanInfo -> Aeson.Value
declToJsonFull decl = case decl of
  -- Type signature
  TypeSig l names ty -> Aeson.object
    [ "type" Aeson..= ("type_sig" :: String)
    , "names" Aeson..= map nameToString names
    , "signature" Aeson..= typeToJson ty
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Data type declaration
  DataDecl l dataOrNew _ declHead qualConDecls _ -> Aeson.object
    [ "type" Aeson..= ("data_decl" :: String)
    , "data_or_new" Aeson..= dataOrNewToString dataOrNew
    , "name" Aeson..= declHeadToString declHead
    , "constructors" Aeson..= map qualConDeclToJson qualConDecls
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Type class declaration
  ClassDecl l _ declHead _ classDecls -> Aeson.object
    [ "type" Aeson..= ("class_decl" :: String)
    , "name" Aeson..= declHeadToString declHead
    , "methods" Aeson..= maybe [] (map classDeclToJson) classDecls
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Instance declaration
  InstDecl l _ instRule instDecls -> Aeson.object
    [ "type" Aeson..= ("instance_decl" :: String)
    , "rule" Aeson..= instRuleToJson instRule
    , "methods" Aeson..= maybe [] (map instDeclToJson) instDecls
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Function binding
  FunBind l matches -> Aeson.object
    [ "type" Aeson..= ("fun_bind" :: String)
    , "matches" Aeson..= map matchToJson matches
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Pattern binding
  PatBind l pat rhs _ -> Aeson.object
    [ "type" Aeson..= ("pat_bind" :: String)
    , "pattern" Aeson..= patToJson pat
    , "rhs" Aeson..= rhsToJson rhs
    , "location" Aeson..= srcSpanToJson l
    ]
  
  -- Type alias
  TypeDecl l declHead ty -> Aeson.object
    [ "type" Aeson..= ("type_alias" :: String)
    , "name" Aeson..= declHeadToString declHead
    , "definition" Aeson..= typeToJson ty
    , "location" Aeson..= srcSpanToJson l
    ]
  
  _ -> Aeson.object
    [ "type" Aeson..= ("unsupported_decl" :: String)
    , "original" Aeson..= show decl
    ]

-- | Convert declaration to JSON (simple version for bindings)
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
altToJson (Alt l pat rhs _) = Aeson.object
  [ "pattern" Aeson..= patToJson pat
  , "rhs" Aeson..= rhsToJson rhs
  , "location" Aeson..= srcSpanToJson l
  ]

-- | Convert qualifier statement to JSON
qualStmtToJson :: QualStmt SrcSpanInfo -> Aeson.Value
qualStmtToJson (QualStmt _ stmt) = stmtToJson stmt
qualStmtToJson _ = Aeson.Null

-- | Convert statement to JSON
stmtToJson :: Stmt SrcSpanInfo -> Aeson.Value
stmtToJson stmt = case stmt of
  Generator l pat expr -> Aeson.object
    [ "type" Aeson..= ("generator" :: String)
    , "pattern" Aeson..= patToJson pat
    , "expression" Aeson..= exprToJson expr
    , "location" Aeson..= srcSpanToJson l
    ]
  Qualifier l expr -> Aeson.object
    [ "type" Aeson..= ("qualifier" :: String)
    , "expression" Aeson..= exprToJson expr
    , "location" Aeson..= srcSpanToJson l
    ]
  LetStmt l binds -> Aeson.object
    [ "type" Aeson..= ("let_stmt" :: String)
    , "bindings" Aeson..= bindsToJson binds
    , "location" Aeson..= srcSpanToJson l
    ]
  _ -> Aeson.object
    [ "type" Aeson..= ("unsupported_stmt" :: String)
    ]

-- | Convert type to JSON
typeToJson :: Type SrcSpanInfo -> Aeson.Value
typeToJson ty = case ty of
  TyFun _ arg res -> Aeson.object
    [ "type" Aeson..= ("type_fun" :: String)
    , "argument" Aeson..= typeToJson arg
    , "result" Aeson..= typeToJson res
    ]
  TyTuple _ Boxed types -> Aeson.object
    [ "type" Aeson..= ("type_tuple" :: String)
    , "elements" Aeson..= map typeToJson types
    ]
  TyList _ ty' -> Aeson.object
    [ "type" Aeson..= ("type_list" :: String)
    , "element" Aeson..= typeToJson ty'
    ]
  TyApp _ t1 t2 -> Aeson.object
    [ "type" Aeson..= ("type_app" :: String)
    , "constructor" Aeson..= typeToJson t1
    , "argument" Aeson..= typeToJson t2
    ]
  TyVar _ name -> Aeson.object
    [ "type" Aeson..= ("type_var" :: String)
    , "name" Aeson..= nameToString name
    ]
  TyCon _ qname -> Aeson.object
    [ "type" Aeson..= ("type_con" :: String)
    , "name" Aeson..= qnameToString qname
    ]
  _ -> Aeson.object
    [ "type" Aeson..= ("unsupported_type" :: String)
    , "original" Aeson..= show ty
    ]

-- | Convert name to string
nameToString :: Name l -> String
nameToString (Ident _ n) = n
nameToString (Symbol _ s) = s

-- | Convert data or newtype to string
dataOrNewToString :: DataOrNew l -> String
dataOrNewToString (DataType _) = "data"
dataOrNewToString (NewType _) = "newtype"

-- | Convert declaration head to string
declHeadToString :: DeclHead l -> String
declHeadToString (DHead _ name) = nameToString name
declHeadToString (DHInfix _ _ name) = nameToString name
declHeadToString (DHParen _ dh) = declHeadToString dh
declHeadToString (DHApp _ dh _) = declHeadToString dh

-- | Convert qualified constructor declaration to JSON
qualConDeclToJson :: QualConDecl SrcSpanInfo -> Aeson.Value
qualConDeclToJson (QualConDecl _ _ _ conDecl) = conDeclToJson conDecl

-- | Convert constructor declaration to JSON
conDeclToJson :: ConDecl SrcSpanInfo -> Aeson.Value
conDeclToJson (ConDecl _ name types) = Aeson.object
  [ "name" Aeson..= nameToString name
  , "types" Aeson..= map typeToJson types
  ]
conDeclToJson (RecDecl _ name fields) = Aeson.object
  [ "name" Aeson..= nameToString name
  , "fields" Aeson..= map fieldDeclToJson fields
  ]
conDeclToJson _ = Aeson.object
  [ "unsupported" Aeson..= True
  ]

-- | Convert field declaration to JSON
fieldDeclToJson :: FieldDecl SrcSpanInfo -> Aeson.Value
fieldDeclToJson (FieldDecl _ names ty) = Aeson.object
  [ "names" Aeson..= map nameToString names
  , "type" Aeson..= typeToJson ty
  ]

-- | Convert instance rule to JSON
instRuleToJson :: InstRule SrcSpanInfo -> Aeson.Value
instRuleToJson (IRule _ _ _ instHead) = instHeadToJson instHead
instRuleToJson _ = Aeson.Null

-- | Convert instance head to JSON
instHeadToJson :: InstHead SrcSpanInfo -> Aeson.Value
instHeadToJson (IHCon _ qname) = Aeson.object
  [ "class" Aeson..= qnameToString qname
  ]
instHeadToJson (IHApp _ ih ty) = Aeson.object
  [ "head" Aeson..= instHeadToJson ih
  , "type" Aeson..= typeToJson ty
  ]
instHeadToJson _ = Aeson.Null

-- | Convert match to JSON
matchToJson :: Match SrcSpanInfo -> Aeson.Value
matchToJson (Match l name pats rhs _) = Aeson.object
  [ "name" Aeson..= nameToString name
  , "patterns" Aeson..= map patToJson pats
  , "rhs" Aeson..= rhsToJson rhs
  , "location" Aeson..= srcSpanToJson l
  ]
matchToJson _ = Aeson.Null

-- | Convert class declaration to JSON
classDeclToJson :: ClassDecl SrcSpanInfo -> Aeson.Value
classDeclToJson (ClsDecl _ decl) = declToJsonFull decl
classDeclToJson _ = Aeson.Null

-- | Convert instance declaration to JSON
instDeclToJson :: InstDecl SrcSpanInfo -> Aeson.Value
instDeclToJson (InsDecl _ decl) = declToJsonFull decl
instDeclToJson _ = Aeson.Null
