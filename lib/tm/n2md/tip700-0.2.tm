# n2md::tip700 -- Markdown nach TIP 700 aus einer nroff-Handbuchseite
#
#   package require n2md::tip700 0.2
#   set md [n2md::tip700::convert $nroffText ?-file datei.n? ?-dir ordner?]
#   set md [n2md::tip700::render $nroffText ?ir?]     ;# wie 0.1, ir wird nicht gebraucht
#   set ix [n2md::tip700::index $ordner]              ;# Befehle/C-Funktionen eines Ordners
#
# Schreibt das Format von tools/man2markdown.tcl (Tcl-Kern, Zweig
# tip-700, Stand 2026-10-25) nach allgemeinen Regeln:
#
#   ---                                YAML-Kopf (.TH, Kommentare, SEE ALSO,
#   CommandName: after                 KEYWORDS)
#   title: after
#   ...
#   ---
#
#   # Name                             .SH, Schreibweise der Woerter wie im Text
#   ::: {.synopsis} :::                Uebersicht als Spans
#   [after]{.cmd} [ms]{.arg} [script]{.optdot}
#   :::
#   [after]{.cmd} [cancel]{.sub} [id]{.arg}     .TP mit ".\" METHOD:" davor
#   : Beschreibung                              erster Absatz
#
#       weiterer Absatz                         4 Leerzeichen, Teil der Definition
#
#       1. Listenpunkt                          .IP (1) unter .RS
#
#   [concat]: concat.md                Linkziele am Ende ([cd], [string match][string])
#
# Seit 0.2 eigener Block- und Inline-Parser nach dem Muster von
# man2markdown.tcl (parseBlock, parseCommand, parseInline, AST2Markdown,
# mdLinks), aber ohne Abbruch: wo man2markdown "exit" ruft oder einen
# Fehler wirft (schmutziges \fB/\fR, unbekannte Uebersichtsmuster,
# fehlende .SH am Ende), wird der Rest als Text ausgegeben. 0.1 setzte
# auf docir::roff/docir::md auf; deren flache Listen kannten keine
# eingerueckten Folgeabsaetze und keine verschachtelten Definitionen.
#
# Nicht uebernommen: die seitenbezogenen Textkorrekturen von man2markdown
# (::ndoc::mdExceptions) und seine Befehlsliste aus [info commands].
# Die Befehle fuer Links kommen aus den Seiten des Eingabeordners (.TH-Name
# und NAME-Abschnitt, siehe index) und aus festen Tabellen unten.

package require Tcl 8.6-

namespace eval n2md::tip700 {
    namespace export convert render index group uriLinks

    # Zustand der laufenden Umwandlung (convert setzt ihn)
    variable P {}
    # Index je Ordner (index)
    variable indexCache
    array set indexCache {}

    # Namen aus NAME-Abschnitten, die keine globalen Befehle sind und
    # deshalb nicht verlinkt werden (configurable.n: Definitionsbefehle
    # nur innerhalb von oo::configurable)
    variable notCommands {configure property}

    # Interne Marken im Rohtext (statt der Zeichen \u00a7 \u2021 \u00a4 von
    # man2markdown, die in Quelltexten vorkommen koennten)
    variable Q  \x01
    variable VS \x02
    variable VE \x03
    # vor einem Begriff, der kein Link werden soll (_md -> _links)
    variable NL \x04

    # ------------------------------------------------------------
    # Feste Tabellen. Vorrang haben jeweils die Seiten des
    # Eingabeordners (index): dann stimmen die Ziele auch fuer 8.6/9.0.
    # ------------------------------------------------------------

    # Tcl-C-Funktion -> Seite (Dateiwurzel). Aus man2markdown.tcl, Zweig
    # tip-700, Stand 2026-10-25 (tclCApiFileMap).
    variable tclCApiFileMap [dict create {*}{
	Tcl_Obj Object
	Tcl_DString DString
	Tcl_Access Access Tcl_AddErrorInfo AddErrInfo Tcl_AddObjErrorInfo AddErrInfo Tcl_AlertNotifier Notifier
	Tcl_Alloc Alloc Tcl_AllocStatBuf FileSystem Tcl_AllowExceptions AllowExc Tcl_AppInit AppInit
	Tcl_AppendAllObjTypes ObjectType Tcl_AppendElement SetResult Tcl_AppendExportList Namespace Tcl_AppendFormatToObj StringObj
	Tcl_AppendLimitedToObj StringObj Tcl_AppendObjToErrorInfo AddErrInfo Tcl_AppendObjToObj StringObj Tcl_AppendPrintfToObj StringObj
	Tcl_AppendResult SetResult Tcl_AppendStringsToObj StringObj Tcl_AppendToObj StringObj Tcl_AppendUnicodeToObj StringObj
	Tcl_AsyncCreate Async Tcl_AsyncDelete Async Tcl_AsyncInvoke Async Tcl_AsyncMark Async
	Tcl_AsyncMarkFromSignal Async Tcl_AsyncReady Async Tcl_AttemptAlloc Alloc Tcl_AttemptCreateHashEntry Hash
	Tcl_AttemptRealloc Alloc Tcl_AttemptSetObjLength StringObj Tcl_BackgroundError BackgdErr Tcl_BackgroundException BackgdErr
	Tcl_BadChannelOption CrtChannel Tcl_BounceRefCount Object Tcl_CallWhenDeleted CallDel Tcl_CancelEval Cancel
	Tcl_CancelIdleCall DoWhenIdle Tcl_Canceled Cancel Tcl_ChannelBlockModeProc CrtChannel Tcl_ChannelBuffered CrtChannel
	Tcl_ChannelClose2Proc CrtChannel Tcl_ChannelFlushProc CrtChannel Tcl_ChannelGetHandleProc CrtChannel Tcl_ChannelGetOptionProc CrtChannel
	Tcl_ChannelHandlerProc CrtChannel Tcl_ChannelInputProc CrtChannel Tcl_ChannelName CrtChannel Tcl_ChannelOutputProc CrtChannel
	Tcl_ChannelSetOptionProc CrtChannel Tcl_ChannelThreadActionProc CrtChannel Tcl_ChannelTruncateProc CrtChannel Tcl_ChannelVersion CrtChannel
	Tcl_ChannelWatchProc CrtChannel Tcl_ChannelWideSeekProc CrtChannel Tcl_Char16Len Utf Tcl_Char16ToUtfDString Utf
	Tcl_Chdir GetCwd Tcl_ClassGetMetadata Class Tcl_ClassSetConstructor Method Tcl_ClassSetDestructor Method
	Tcl_ClassSetMetadata Class Tcl_ClearChannelHandlers CrtChannel Tcl_Close OpenFileChnl Tcl_CloseEx OpenFileChnl
	Tcl_CommandComplete CmdCmplt Tcl_CommandTraceInfo TraceCmd Tcl_Concat Concat Tcl_ConcatObj StringObj
	Tcl_ConditionFinalize Thread Tcl_ConditionNotify Thread Tcl_ConditionWait Thread Tcl_ConsolePanic Panic
	Tcl_ConvertCountedElement SplitList Tcl_ConvertElement SplitList Tcl_ConvertToType ObjectType Tcl_CopyObjectInstance Class
	Tcl_CreateAlias CrtAlias Tcl_CreateAliasObj CrtAlias Tcl_CreateChannel CrtChannel Tcl_CreateChannelHandler CrtChnlHdlr
	Tcl_CreateChild CrtAlias Tcl_CreateCloseHandler CrtCloseHdlr Tcl_CreateCommand CrtCommand Tcl_CreateEncoding Encoding
	Tcl_CreateEnsemble Ensemble Tcl_CreateEventSource Notifier Tcl_CreateExitHandler Exit Tcl_CreateFileHandler CrtFileHdlr
	Tcl_CreateHashEntry Hash Tcl_CreateInterp CrtInterp Tcl_CreateNamespace Namespace Tcl_CreateObjCommand CrtObjCmd
	Tcl_CreateObjCommand2 CrtObjCmd Tcl_CreateObjTrace CrtTrace Tcl_CreateObjTrace2 CrtTrace Tcl_CreateThread Thread
	Tcl_CreateThreadExitHandler Exit Tcl_CreateTimerHandler CrtTimerHdlr Tcl_CreateTrace CrtTrace Tcl_CutChannel CrtChannel
	Tcl_DStringAppend DString Tcl_DStringAppendElement DString Tcl_DStringEndSublist DString Tcl_DStringFree DString
	Tcl_DStringGetResult DString Tcl_DStringInit DString Tcl_DStringLength DString Tcl_DStringResult DString
	Tcl_DStringSetLength DString Tcl_DStringStartSublist DString Tcl_DStringToObj DString Tcl_DStringValue DString
	Tcl_DecrRefCount Object Tcl_DeleteAssocData AssocData Tcl_DeleteChannelHandler CrtChnlHdlr Tcl_DeleteCloseHandler CrtCloseHdlr
	Tcl_DeleteCommand CrtObjCmd Tcl_DeleteCommandFromToken CrtObjCmd Tcl_DeleteEventSource Notifier Tcl_DeleteEvents Notifier
	Tcl_DeleteExitHandler Exit Tcl_DeleteFileHandler CrtFileHdlr Tcl_DeleteHashEntry Hash Tcl_DeleteHashTable Hash
	Tcl_DeleteInterp CrtInterp Tcl_DeleteNamespace Namespace Tcl_DeleteThreadExitHandler Exit Tcl_DeleteTimerHandler CrtTimerHdlr
	Tcl_DeleteTrace CrtTrace Tcl_DetachChannel OpenFileChnl Tcl_DetachPids DetachPids Tcl_DictObjDone DictObj
	Tcl_DictObjFirst DictObj Tcl_DictObjGet DictObj Tcl_DictObjNext DictObj Tcl_DictObjPut DictObj
	Tcl_DictObjPutKeyList DictObj Tcl_DictObjRemove DictObj Tcl_DictObjRemoveKeyList DictObj Tcl_DictObjSize DictObj
	Tcl_DiscardInterpState SaveInterpState Tcl_DoOneEvent DoOneEvent Tcl_DoWhenIdle DoWhenIdle Tcl_DontCallWhenDeleted CallDel
	Tcl_DumpActiveMemory DumpActiveMemory Tcl_DuplicateObj Object Tcl_Eof OpenFileChnl Tcl_ErrnoId SetErrno
	Tcl_ErrnoMsg SetErrno Tcl_Eval Eval Tcl_EvalEx Eval Tcl_EvalFile Eval
	Tcl_EvalObjEx Eval Tcl_EvalObjv Eval Tcl_EvalTokensStandard ParseCmd Tcl_EventuallyFree Preserve
	Tcl_Exit Exit Tcl_ExitThread Exit Tcl_Export Namespace Tcl_ExposeCommand CrtAlias
	Tcl_ExprBoolean ExprLong Tcl_ExprBooleanObj ExprLongObj Tcl_ExprDouble ExprLong Tcl_ExprDoubleObj ExprLongObj
	Tcl_ExprLong ExprLong Tcl_ExprLongObj ExprLongObj Tcl_ExprObj ExprLongObj Tcl_ExprString ExprLong
	Tcl_ExternalToUtf Encoding Tcl_ExternalToUtfDString Encoding Tcl_ExternalToUtfDStringEx Encoding Tcl_FSAccess FileSystem
	Tcl_FSChdir FileSystem Tcl_FSConvertToPathType FileSystem Tcl_FSCopyDirectory FileSystem Tcl_FSCopyFile FileSystem
	Tcl_FSCreateDirectory FileSystem Tcl_FSData FileSystem Tcl_FSDeleteFile FileSystem Tcl_FSEqualPaths FileSystem
	Tcl_FSEvalFile FileSystem Tcl_FSEvalFileEx FileSystem Tcl_FSFileAttrStrings FileSystem Tcl_FSFileAttrsGet FileSystem
	Tcl_FSFileAttrsSet FileSystem Tcl_FSFileSystemInfo FileSystem Tcl_FSGetCwd FileSystem Tcl_FSGetFileSystemForPath FileSystem
	Tcl_FSGetInternalRep FileSystem Tcl_FSGetNativePath FileSystem Tcl_FSGetNormalizedPath FileSystem Tcl_FSGetPathType FileSystem
	Tcl_FSGetTranslatedPath FileSystem Tcl_FSGetTranslatedStringPath FileSystem Tcl_FSJoinPath FileSystem Tcl_FSJoinToPath FileSystem
	Tcl_FSLink FileSystem Tcl_FSListVolumes FileSystem Tcl_FSLoadFile FileSystem Tcl_FSLstat FileSystem
	Tcl_FSMatchInDirectory FileSystem Tcl_FSMountsChanged FileSystem Tcl_FSNewNativePath FileSystem Tcl_FSOpenFileChannel FileSystem
	Tcl_FSPathSeparator FileSystem Tcl_FSRegister FileSystem Tcl_FSRemoveDirectory FileSystem Tcl_FSRenameFile FileSystem
	Tcl_FSSplitPath FileSystem Tcl_FSStat FileSystem Tcl_FSTildeExpand FileSystem Tcl_FSUnloadFile FileSystem
	Tcl_FSUnregister FileSystem Tcl_FSUtime FileSystem Tcl_FetchInternalRep ObjectType Tcl_Finalize Exit
	Tcl_FinalizeNotifier Notifier Tcl_FinalizeThread Exit Tcl_FindCommand Namespace Tcl_FindEnsemble Ensemble
	Tcl_FindExecutable FindExec Tcl_FindHashEntry Hash Tcl_FindNamespace Namespace Tcl_FindSymbol Load
	Tcl_FirstHashEntry Hash Tcl_Flush OpenFileChnl Tcl_ForgetImport Namespace Tcl_Format StringObj
	Tcl_Free Alloc Tcl_FreeEncoding Encoding Tcl_FreeInternalRep ObjectType Tcl_FreeParse ParseCmd
	Tcl_GetAccessTimeFromStat FileSystem Tcl_GetAliasObj CrtAlias Tcl_GetAssocData AssocData Tcl_GetBignumFromObj IntObj
	Tcl_GetBlockSizeFromStat FileSystem Tcl_GetBlocksFromStat FileSystem Tcl_GetBoolFromObj BoolObj Tcl_GetBoolean GetInt
	Tcl_GetBooleanFromObj BoolObj Tcl_GetByteArrayFromObj ByteArrObj Tcl_GetBytesFromObj ByteArrObj Tcl_GetChangeTimeFromStat FileSystem
	Tcl_GetChannel OpenFileChnl Tcl_GetChannelBufferSize CrtChannel Tcl_GetChannelError SetChanErr Tcl_GetChannelErrorInterp SetChanErr
	Tcl_GetChannelHandle CrtChannel Tcl_GetChannelInstanceData CrtChannel Tcl_GetChannelMode CrtChannel Tcl_GetChannelName CrtChannel
	Tcl_GetChannelNames OpenFileChnl Tcl_GetChannelNamesEx OpenFileChnl Tcl_GetChannelOption OpenFileChnl Tcl_GetChannelThread CrtChannel
	Tcl_GetChannelType CrtChannel Tcl_GetCharLength StringObj Tcl_GetChild CrtAlias Tcl_GetClassAsObject Class
	Tcl_GetCommandFromObj CrtObjCmd Tcl_GetCommandFullName CrtObjCmd Tcl_GetCommandInfo CrtObjCmd Tcl_GetCommandInfoFromToken CrtObjCmd
	Tcl_GetCommandName CrtObjCmd Tcl_GetCurrentNamespace Namespace Tcl_GetCurrentThread Notifier Tcl_GetCwd GetCwd
	Tcl_GetDeviceTypeFromStat FileSystem Tcl_GetDouble GetInt Tcl_GetDoubleFromObj DoubleObj Tcl_GetEncoding Encoding
	Tcl_GetEncodingFromObj Encoding Tcl_GetEncodingName Encoding Tcl_GetEncodingNameForUser Encoding Tcl_GetEncodingNameFromEnvironment Encoding
	Tcl_GetEncodingNames Encoding Tcl_GetEncodingSearchPath Encoding Tcl_GetEnsembleFlags Ensemble Tcl_GetEnsembleMappingDict Ensemble
	Tcl_GetEnsembleNamespace Ensemble Tcl_GetEnsembleParameterList Ensemble Tcl_GetEnsembleSubcommandList Ensemble Tcl_GetEnsembleUnknownHandler Ensemble
	Tcl_GetErrno SetErrno Tcl_GetErrorLine AddErrInfo Tcl_GetFSDeviceFromStat FileSystem Tcl_GetFSInodeFromStat FileSystem
	Tcl_GetGlobalNamespace Namespace Tcl_GetGroupIdFromStat FileSystem Tcl_GetHashKey Hash Tcl_GetHashValue Hash
	Tcl_GetHostName GetHostName Tcl_GetIndexFromObj GetIndex Tcl_GetIndexFromObjStruct GetIndex Tcl_GetInt GetInt
	Tcl_GetIntForIndex IntObj Tcl_GetIntFromObj IntObj Tcl_GetInterpPath CrtAlias Tcl_GetLinkCountFromStat FileSystem
	Tcl_GetLongFromObj IntObj Tcl_GetMemoryInfo Alloc Tcl_GetModeFromStat FileSystem Tcl_GetModificationTimeFromStat FileSystem
	Tcl_GetNameOfExecutable FindExec Tcl_GetNamespaceUnknownHandler Namespace Tcl_GetNumber Number Tcl_GetNumberFromObj Number
	Tcl_GetObjResult SetResult Tcl_GetObjType ObjectType Tcl_GetObjectAsClass Class Tcl_GetObjectCommand Class
	Tcl_GetObjectFromObj Class Tcl_GetObjectName Class Tcl_GetObjectNamespace Class Tcl_GetOpenFile GetOpnFl
	Tcl_GetParent CrtAlias Tcl_GetPathType SplitPath Tcl_GetRange StringObj Tcl_GetRegExpFromObj RegExp
	Tcl_GetReturnOptions AddErrInfo Tcl_GetServiceMode Notifier Tcl_GetSizeFromStat FileSystem Tcl_GetSizeIntFromObj IntObj
	Tcl_GetStackedChannel ChnlStack Tcl_GetStartupScript Tcl_Main Tcl_GetStdChannel GetStdChan Tcl_GetString StringObj
	Tcl_GetStringFromObj StringObj Tcl_GetStringResult SetResult Tcl_GetThreadData Thread Tcl_GetTime GetTime
	Tcl_GetTopChannel ChnlStack Tcl_GetUniChar StringObj Tcl_GetUnicode StringObj Tcl_GetUnicodeFromObj StringObj
	Tcl_GetUserIdFromStat FileSystem Tcl_GetVar SetVar Tcl_GetVar2 SetVar Tcl_GetVar2Ex SetVar
	Tcl_GetVersion GetVersion Tcl_GetWideIntFromObj IntObj Tcl_GetWideUIntFromObj IntObj Tcl_Gets OpenFileChnl
	Tcl_GetsObj OpenFileChnl Tcl_GlobalEval Eval Tcl_GlobalEvalObj Eval Tcl_HasStringRep ObjectType
	Tcl_HashStats Hash Tcl_HideCommand CrtAlias Tcl_Import Namespace Tcl_IncrRefCount Object
	Tcl_Init Init Tcl_InitCustomHashTable Hash Tcl_InitHashTable Hash Tcl_InitMemory DumpActiveMemory
	Tcl_InitNotifier Notifier Tcl_InitObjHashTable Hash Tcl_InitStringRep ObjectType Tcl_InitStubs InitStubs
	Tcl_InitSubsystems InitSubSyst Tcl_InputBlocked OpenFileChnl Tcl_InputBuffered OpenFileChnl Tcl_InterpActive CrtInterp
	Tcl_InterpDeleted CrtInterp Tcl_InvalidateStringRep Object Tcl_IsChannelExisting CrtChannel Tcl_IsChannelRegistered CrtChannel
	Tcl_IsChannelShared CrtChannel Tcl_IsEmpty StringObj Tcl_IsEnsemble Ensemble Tcl_IsSafe CrtAlias
	Tcl_IsShared Object Tcl_IsStandardChannel OpenFileChnl Tcl_JoinPath SplitPath Tcl_JoinThread Thread
	Tcl_LimitAddHandler Limit Tcl_LimitCheck Limit Tcl_LimitExceeded Limit Tcl_LimitGetCommands Limit
	Tcl_LimitGetGranularity Limit Tcl_LimitGetTime Limit Tcl_LimitReady Limit Tcl_LimitRemoveHandler Limit
	Tcl_LimitSetCommands Limit Tcl_LimitSetGranularity Limit Tcl_LimitSetTime Limit Tcl_LimitTypeEnabled Limit
	Tcl_LimitTypeExceeded Limit Tcl_LimitTypeReset Limit Tcl_LimitTypeSet Limit Tcl_LinkArray LinkVar
	Tcl_LinkVar LinkVar Tcl_ListObjAppendElement ListObj Tcl_ListObjAppendList ListObj Tcl_ListObjGetElements ListObj
	Tcl_ListObjIndex ListObj Tcl_ListObjLength ListObj Tcl_ListObjRange ListObj Tcl_ListObjRepeat ListObj
	Tcl_ListObjReplace ListObj Tcl_ListObjReverse ListObj Tcl_LoadFile Load Tcl_LogCommandInfo AddErrInfo
	Tcl_Main Tcl_Main Tcl_MainEx Tcl_Main Tcl_MainExW Tcl_Main Tcl_MakeFileChannel OpenFileChnl
	Tcl_MakeTcpClientChannel OpenTcp Tcl_Merge SplitList Tcl_MethodDeclarerClass Method Tcl_MethodDeclarerObject Method
	Tcl_MethodIsPrivate Method Tcl_MethodIsPublic Method Tcl_MethodIsType Method Tcl_MethodIsType2 Method
	Tcl_MethodName Method Tcl_MutexFinalize Thread Tcl_MutexLock Thread Tcl_MutexUnlock Thread
	Tcl_NRAddCallback NRE Tcl_NRCallObjProc NRE Tcl_NRCallObjProc2 NRE Tcl_NRCmdSwap NRE
	Tcl_NRCreateCommand NRE Tcl_NRCreateCommand2 NRE Tcl_NREvalObj NRE Tcl_NREvalObjv NRE
	Tcl_NRExprObj NRE Tcl_NewBignumObj IntObj Tcl_NewBooleanObj BoolObj Tcl_NewByteArrayObj ByteArrObj
	Tcl_NewDictObj DictObj Tcl_NewDoubleObj DoubleObj Tcl_NewInstanceMethod Method Tcl_NewInstanceMethod2 Method
	Tcl_NewIntObj IntObj Tcl_NewListObj ListObj Tcl_NewLongObj IntObj Tcl_NewMethod Method
	Tcl_NewMethod2 Method Tcl_NewObj Object Tcl_NewObjectInstance Class Tcl_NewStringObj StringObj
	Tcl_NewUnicodeObj StringObj Tcl_NewWideIntObj IntObj Tcl_NewWideUIntObj IntObj Tcl_NextHashEntry Hash
	Tcl_NotifyChannel CrtChannel Tcl_NumUtfChars Utf Tcl_OOInitStubs OOInitStubs Tcl_ObjGetVar2 SetVar
	Tcl_ObjPrintf StringObj Tcl_ObjSetVar2 SetVar Tcl_ObjectContextInvokeNext Method Tcl_ObjectContextIsFiltering Method
	Tcl_ObjectContextMethod Method Tcl_ObjectContextObject Method Tcl_ObjectContextSkippedArgs Method Tcl_ObjectDeleted Class
	Tcl_ObjectGetMetadata Class Tcl_ObjectGetMethodNameMapper Class Tcl_ObjectSetMetadata Class Tcl_ObjectSetMethodNameMapper Class
	Tcl_OpenCommandChannel OpenFileChnl Tcl_OpenFileChannel OpenFileChnl Tcl_OpenTcpClient OpenTcp Tcl_OpenTcpServer OpenTcp
	Tcl_OpenTcpServerEx OpenTcp Tcl_OutputBuffered OpenFileChnl Tcl_Panic Panic Tcl_ParseArgsObjv ParseArgs
	Tcl_ParseBraces ParseCmd Tcl_ParseCommand ParseCmd Tcl_ParseExpr ParseCmd Tcl_ParseQuotedString ParseCmd
	Tcl_ParseVar ParseCmd Tcl_ParseVarName ParseCmd Tcl_PkgPresent PkgRequire Tcl_PkgPresentEx PkgRequire
	Tcl_PkgProvide PkgRequire Tcl_PkgProvideEx PkgRequire Tcl_PkgRequire PkgRequire Tcl_PkgRequireEx PkgRequire
	Tcl_PkgRequireProc PkgRequire Tcl_PosixError AddErrInfo Tcl_Preserve Preserve Tcl_PrintDouble PrintDbl
	Tcl_PutEnv Environment Tcl_QueryTimeProc GetTime Tcl_QueueEvent Notifier Tcl_Read OpenFileChnl
	Tcl_ReadChars OpenFileChnl Tcl_ReadRaw OpenFileChnl Tcl_Realloc Alloc Tcl_ReapDetachedProcs DetachPids
	Tcl_RecordAndEval RecordEval Tcl_RecordAndEvalObj RecEvalObj Tcl_RegExpCompile RegExp Tcl_RegExpExec RegExp
	Tcl_RegExpExecObj RegExp Tcl_RegExpGetInfo RegExp Tcl_RegExpMatch RegExp Tcl_RegExpMatchObj RegExp
	Tcl_RegExpRange RegExp Tcl_RegisterChannel OpenFileChnl Tcl_RegisterConfig RegConfig Tcl_RegisterObjType ObjectType
	Tcl_Release Preserve Tcl_ResetResult SetResult Tcl_RestoreInterpState SaveInterpState Tcl_SaveInterpState SaveInterpState
	Tcl_ScanCountedElement SplitList Tcl_ScanElement SplitList Tcl_Seek OpenFileChnl Tcl_ServiceAll Notifier
	Tcl_ServiceEvent Notifier Tcl_ServiceModeHook Notifier Tcl_SetAssocData AssocData Tcl_SetBignumObj IntObj
	Tcl_SetBooleanObj BoolObj Tcl_SetByteArrayLength ByteArrObj Tcl_SetByteArrayObj ByteArrObj Tcl_SetChannelBufferSize CrtChannel
	Tcl_SetChannelError SetChanErr Tcl_SetChannelErrorInterp SetChanErr Tcl_SetChannelOption OpenFileChnl Tcl_SetCommandInfo CrtObjCmd
	Tcl_SetCommandInfoFromToken CrtObjCmd Tcl_SetDoubleObj DoubleObj Tcl_SetEncodingSearchPath Encoding Tcl_SetEnsembleFlags Ensemble
	Tcl_SetEnsembleMappingDict Ensemble Tcl_SetEnsembleParameterList Ensemble Tcl_SetEnsembleSubcommandList Ensemble Tcl_SetEnsembleUnknownHandler Ensemble
	Tcl_SetErrno SetErrno Tcl_SetErrorCode AddErrInfo Tcl_SetErrorLine AddErrInfo Tcl_SetExitProc Exit
	Tcl_SetHashValue Hash Tcl_SetIntObj IntObj Tcl_SetListObj ListObj Tcl_SetLongObj IntObj
	Tcl_SetMainLoop Tcl_Main Tcl_SetMaxBlockTime Notifier Tcl_SetNamespaceUnknownHandler Namespace Tcl_SetNotifier Notifier
	Tcl_SetObjErrorCode AddErrInfo Tcl_SetObjLength StringObj Tcl_SetObjResult SetResult Tcl_SetPanicProc Panic
	Tcl_SetRecursionLimit SetRecLmt Tcl_SetResult SetResult Tcl_SetReturnOptions AddErrInfo Tcl_SetServiceMode Notifier
	Tcl_SetStartupScript Tcl_Main Tcl_SetStdChannel GetStdChan Tcl_SetStringObj StringObj Tcl_SetSystemEncoding Encoding
	Tcl_SetTimeProc GetTime Tcl_SetTimer Notifier Tcl_SetUnicodeObj StringObj Tcl_SetVar SetVar
	Tcl_SetVar2 SetVar Tcl_SetVar2Ex SetVar Tcl_SetWideIntObj IntObj Tcl_SetWideUIntObj IntObj
	Tcl_SignalId Signal Tcl_SignalMsg Signal Tcl_Sleep Sleep Tcl_SourceRCFile SourceRCFile
	Tcl_SpliceChannel CrtChannel Tcl_SplitList SplitList Tcl_SplitPath SplitPath Tcl_StackChannel ChnlStack
	Tcl_StandardChannels StdChannels Tcl_Stat Access Tcl_StaticLibrary StaticLibrary Tcl_StaticPackage StaticLibrary
	Tcl_StoreInternalRep ObjectType Tcl_StringCaseMatch StrMatch Tcl_StringMatch StrMatch Tcl_SubstObj SubstObj
	Tcl_TakeBignumFromObj IntObj Tcl_Tell OpenFileChnl Tcl_ThreadAlert Notifier Tcl_ThreadQueueEvent Notifier
	Tcl_TraceCommand TraceCmd Tcl_TraceVar TraceVar Tcl_TraceVar2 TraceVar Tcl_TransferResult SetResult
	Tcl_TranslateFileName Translate Tcl_TruncateChannel OpenFileChnl Tcl_Ungets OpenFileChnl Tcl_UniChar Utf
	Tcl_UniCharAtIndex Utf Tcl_UniCharCaseMatch Utf Tcl_UniCharIsAlnum UniCharIsAlpha Tcl_UniCharIsAlpha UniCharIsAlpha
	Tcl_UniCharIsControl UniCharIsAlpha Tcl_UniCharIsDigit UniCharIsAlpha Tcl_UniCharIsGraph UniCharIsAlpha Tcl_UniCharIsLower UniCharIsAlpha
	Tcl_UniCharIsPrint UniCharIsAlpha Tcl_UniCharIsPunct UniCharIsAlpha Tcl_UniCharIsSpace UniCharIsAlpha Tcl_UniCharIsUpper UniCharIsAlpha
	Tcl_UniCharIsWordChar UniCharIsAlpha Tcl_UniCharLen Utf Tcl_UniCharNcasecmp Utf Tcl_UniCharNcmp Utf
	Tcl_UniCharToLower ToUpper Tcl_UniCharToTitle ToUpper Tcl_UniCharToUpper ToUpper Tcl_UniCharToUtf Utf
	Tcl_UniCharToUtfDString Utf Tcl_UnlinkVar LinkVar Tcl_UnregisterChannel OpenFileChnl Tcl_UnsetVar SetVar
	Tcl_UnsetVar2 SetVar Tcl_UnstackChannel ChnlStack Tcl_UntraceCommand TraceCmd Tcl_UntraceVar TraceVar
	Tcl_UntraceVar2 TraceVar Tcl_UpVar UpVar Tcl_UpVar2 UpVar Tcl_UpdateLinkedVar LinkVar
	Tcl_UtfAtIndex Utf Tcl_UtfBackslash Utf Tcl_UtfCharComplete Utf Tcl_UtfFindFirst Utf
	Tcl_UtfFindLast Utf Tcl_UtfNcasecmp Utf Tcl_UtfNcmp Utf Tcl_UtfNext Utf
	Tcl_UtfPrev Utf Tcl_UtfToChar16 Utf Tcl_UtfToChar16DString Utf Tcl_UtfToExternal Encoding
	Tcl_UtfToExternalDString Encoding Tcl_UtfToExternalDStringEx Encoding Tcl_UtfToLower ToUpper Tcl_UtfToNormalized UnicodeNormalize
	Tcl_UtfToNormalizedDString UnicodeNormalize Tcl_UtfToTitle ToUpper Tcl_UtfToUniChar Utf Tcl_UtfToUniCharDString Utf
	Tcl_UtfToUpper ToUpper Tcl_UtfToWChar Utf Tcl_UtfToWCharDString Utf Tcl_ValidateAllMemory DumpActiveMemory
	Tcl_VarEval Eval Tcl_VarTraceInfo TraceVar Tcl_VarTraceInfo2 TraceVar Tcl_WCharLen Utf
	Tcl_WCharToUtfDString Utf Tcl_WaitForEvent Notifier Tcl_WaitPid DetachPids Tcl_WinConvertError SetErrno
	Tcl_Write OpenFileChnl Tcl_WriteChars OpenFileChnl Tcl_WriteObj OpenFileChnl Tcl_WriteRaw OpenFileChnl
	Tcl_WrongNumArgs WrongNumArgs Tcl_ZlibAdler2 TclZlib Tcl_ZlibCRC2 TclZlib Tcl_ZlibDeflate TclZlib
	Tcl_ZlibInflate TclZlib Tcl_ZlibStreamChecksum TclZlib Tcl_ZlibStreamClose TclZlib Tcl_ZlibStreamEof TclZlib
	Tcl_ZlibStreamGet TclZlib Tcl_ZlibStreamGetCommandName TclZlib Tcl_ZlibStreamInit TclZlib Tcl_ZlibStreamPut TclZlib
	TclZipfs_AppHook zipfs TclZipfs_Mount zipfs TclZipfs_MountBuffer zipfs Tcl_zipfsUnmount zipfs
    }]

    # Tk-C-Funktion -> Seite. Aus man2markdown.tcl, Zweig tip-700, Stand
    # 2026-10-25 (tkCApiFileMap).
    variable tkCApiFileMap [dict create {*}{
	Tk_3DBorderColor 3DBorder Tk_3DBorderGC 3DBorder Tk_3DHorizontalBevel 3DBorder Tk_3DVerticalBevel 3DBorder
	Tk_AddOption AddOption Tk_Alloc3DBorderFromObj 3DBorder Tk_AllocBitmapFromObj GetBitmap Tk_AllocColorFromObj GetColor
	Tk_AllocCursorFromObj GetCursor Tk_AllocFontFromObj GetFont Tk_AlwaysShowSelection WindowId Tk_AttachHWND GetHWND
	Tk_Attributes WindowId Tk_BindEvent BindTable Tk_CanvasDrawableCoords CanvTkwin Tk_CanvasEventuallyRedraw CanvTkwin
	Tk_CanvasGetCoord CanvTkwin Tk_CanvasPsBitmap CanvPsY Tk_CanvasPsColor CanvPsY Tk_CanvasPsFont CanvPsY
	Tk_CanvasPsPath CanvPsY Tk_CanvasPsStipple CanvPsY Tk_CanvasPsY CanvPsY Tk_CanvasSetStippleOrigin CanvTkwin
	Tk_CanvasTagsOption CanvTkwin Tk_CanvasTextInfo CanvTxtInfo Tk_CanvasTkwin CanvTkwin Tk_CanvasWindowCoords CanvTkwin
	Tk_ChangeWindowAttributes ConfigWind Tk_Changes WindowId Tk_CharBbox TextLayout Tk_Class SetClass
	Tk_ClearSelection ClrSelect Tk_ClipDrawableToRect 3DBorder Tk_ClipboardAppend Clipboard Tk_ClipboardClear Clipboard
	Tk_CollapseMotionEvents QWinEvent Tk_Colormap WindowId Tk_ComputeTextLayout TextLayout Tk_ConfigureInfo ConfigWidg
	Tk_ConfigureValue ConfigWidg Tk_ConfigureWidget ConfigWidg Tk_ConfigureWindow ConfigWind Tk_CoordsToWindow CoordToWin
	Tk_CreateBinding BindTable Tk_CreateBindingTable BindTable Tk_CreateClientMessageHandler CrtCmHdlr Tk_CreateErrorHandler CrtErrHdlr
	Tk_CreateEventHandler EventHndlr Tk_CreateGenericHandler CrtGenHdlr Tk_CreateImageType CrtImgType Tk_CreateItemType CrtItemType
	Tk_CreateOptionTable SetOptions Tk_CreatePhotoImageFormat CrtPhImgFmt Tk_CreateSelHandler CrtSelHdlr Tk_CreateWindow CrtWindow
	Tk_CreateWindowFromPath CrtWindow Tk_DefineBitmap GetBitmap Tk_DefineCursor ConfigWind Tk_DeleteAllBindings BindTable
	Tk_DeleteBinding BindTable Tk_DeleteBindingTable BindTable Tk_DeleteClientMessageHandler CrtCmHdlr Tk_DeleteErrorHandler CrtErrHdlr
	Tk_DeleteEventHandler EventHndlr Tk_DeleteGenericHandler CrtGenHdlr Tk_DeleteImage DeleteImg Tk_DeleteOptionTable SetOptions
	Tk_DeleteSelHandler CrtSelHdlr Tk_Depth WindowId Tk_DestroyWindow CrtWindow Tk_Display WindowId
	Tk_DisplayName WindowId Tk_DistanceToTextLayout TextLayout Tk_Draw3DPolygon 3DBorder Tk_Draw3DRectangle 3DBorder
	Tk_DrawChars MeasureChar Tk_DrawCharsInContext MeasureChar Tk_DrawFocusHighlight DrawFocHlt Tk_DrawHighlightBorder 3DBorder
	Tk_DrawTextLayout TextLayout Tk_Fill3DPolygon 3DBorder Tk_Fill3DRectangle 3DBorder Tk_FindPhoto FindPhoto
	Tk_FontGetDescription GetFont Tk_FontId FontId Tk_Free3DBorder 3DBorder Tk_Free3DBorderFromObj 3DBorder
	Tk_FreeBitmap GetBitmap Tk_FreeBitmapFromObj GetBitmap Tk_FreeColor GetColor Tk_FreeColorFromObj GetColor
	Tk_FreeColormap GetClrmap Tk_FreeConfigOptions SetOptions Tk_FreeCursor GetCursor Tk_FreeCursorFromObj GetCursor
	Tk_FreeFont GetFont Tk_FreeFontFromObj GetFont Tk_FreeGC GetGC Tk_FreeImage GetImage
	Tk_FreeOptions ConfigWidg Tk_FreePixmap GetPixmap Tk_FreeSavedOptions SetOptions Tk_FreeTextLayout TextLayout
	Tk_GeometryRequest GeomReq Tk_Get3DBorder 3DBorder Tk_Get3DBorderColors 3DBorder Tk_Get3DBorderFromObj 3DBorder
	Tk_GetAllBindings BindTable Tk_GetAnchor GetAnchor Tk_GetAnchorFromObj GetAnchor Tk_GetAtomName InternAtom
	Tk_GetBinding BindTable Tk_GetBitmap GetBitmap Tk_GetBitmapFromObj GetBitmap Tk_GetButtonMask EventHndlr
	Tk_GetCapStyle GetCapStyl Tk_GetColor GetColor Tk_GetColorByValue GetColor Tk_GetColorFromObj GetColor
	Tk_GetColormap GetClrmap Tk_GetCursor GetCursor Tk_GetCursorFromData GetCursor Tk_GetCursorFromObj GetCursor
	Tk_GetDash GetDash Tk_GetDoublePixelsFromObj GetPixels Tk_GetFont GetFont Tk_GetFontFromObj GetFont
	Tk_GetFontMetrics FontId Tk_GetGC GetGC Tk_GetHINSTANCE GetHINSTANCE Tk_GetHWND GetHWND
	Tk_GetImage GetImage Tk_GetImageModelData CrtImgType Tk_GetItemTypes CrtItemType Tk_GetJoinStyle GetJoinStl
	Tk_GetJustify GetJustify Tk_GetJustifyFromObj GetJustify Tk_GetMMFromObj GetPixels Tk_GetNumMainWindows MainWin
	Tk_GetOption GetOption Tk_GetOptionInfo SetOptions Tk_GetOptionValue SetOptions Tk_GetOtherWindow WinUtil
	Tk_GetPixels GetPixels Tk_GetPixelsFromObj GetPixels Tk_GetPixmap GetPixmap Tk_GetRelief GetRelief
	Tk_GetReliefFromObj GetRelief Tk_GetRootCoords GetRootCrd Tk_GetScreenMM GetPixels Tk_GetScrollInfo GetScroll
	Tk_GetScrollInfoObj GetScroll Tk_GetSelection GetSelect Tk_GetUid GetUid Tk_GetUserInactiveTime Inactive
	Tk_GetVRootGeometry GetVRoot Tk_GetVisual GetVisual Tk_Grab Grab Tk_HWNDToWindow HWNDToWindow
	Tk_HandleEvent HandleEvent Tk_Height WindowId Tk_IdToWindow IdToWindow Tk_ImageChanged ImgChanged
	Tk_Init Tk_Init Tk_InitConsoleChannels CrtConsoleChan Tk_InitOptions SetOptions Tk_InitStubs TkInitStubs
	Tk_InternAtom InternAtom Tk_InternalBorderBottom WindowId Tk_InternalBorderLeft WindowId Tk_InternalBorderRight WindowId
	Tk_InternalBorderTop WindowId Tk_Interp WindowId Tk_IntersectTextLayout TextLayout Tk_IsContainer WindowId
	Tk_IsEmbedded WindowId Tk_IsMapped WindowId Tk_IsTopLevel WindowId Tk_Main Tk_Main
	Tk_MainLoop MainLoop Tk_MainWindow MainWin Tk_MaintainGeometry MaintGeom Tk_MakeContainer WinUtil
	Tk_MakeWindow WinUtil Tk_MakeWindowExist CrtWindow Tk_ManageGeometry ManageGeom Tk_MapWindow MapWindow
	Tk_MeasureChars MeasureChar Tk_MeasureCharsInContext MeasureChar Tk_MinReqHeight WindowId Tk_MinReqWidth WindowId
	Tk_MoveResizeWindow ConfigWind Tk_MoveToplevelWindow MoveToplev Tk_MoveWindow ConfigWind Tk_Name Name
	Tk_NameOf3DBorder 3DBorder Tk_NameOfAnchor GetAnchor Tk_NameOfBitmap GetBitmap Tk_NameOfCapStyle GetCapStyl
	Tk_NameOfColor GetColor Tk_NameOfCursor GetCursor Tk_NameOfFont GetFont Tk_NameOfImage NameOfImg
	Tk_NameOfJoinStyle GetJoinStl Tk_NameOfJustify GetJustify Tk_NameOfRelief GetRelief Tk_NameToWindow Name
	Tk_NewWindowObj WindowId Tk_OwnSelection OwnSelect Tk_Parent WindowId Tk_ParseArgv ParseArgv
	Tk_PathName Name Tk_PhotoBlank FindPhoto Tk_PhotoExpand FindPhoto Tk_PhotoGetImage FindPhoto
	Tk_PhotoGetSize FindPhoto Tk_PhotoPutBlock FindPhoto Tk_PhotoPutZoomedBlock FindPhoto Tk_PhotoSetSize FindPhoto
	Tk_PointToChar TextLayout Tk_PostscriptFontName FontId Tk_PreserveColormap GetClrmap Tk_QueueWindowEvent QWinEvent
	Tk_RedrawImage GetImage Tk_ReqHeight WindowId Tk_ReqWidth WindowId Tk_ResetUserInactiveTime Inactive
	Tk_ResizeWindow ConfigWind Tk_RestackWindow Restack Tk_RestoreSavedOptions SetOptions Tk_RestrictEvents RestrictEv
	Tk_SafeInit Tk_Init Tk_Screen WindowId Tk_ScreenNumber WindowId Tk_SendVirtualEvent EventHndlr
	Tk_SetAppName SetAppName Tk_SetBackgroundFromBorder 3DBorder Tk_SetCaretPos SetCaret Tk_SetClass SetClass
	Tk_SetClassProcs SetClassProcs Tk_SetGrid SetGrid Tk_SetInternalBorder GeomReq Tk_SetInternalBorderEx GeomReq
	Tk_SetMinimumRequestSize GeomReq Tk_SetOptions SetOptions Tk_SetWindowBackground ConfigWind Tk_SetWindowBackgroundPixmap ConfigWind
	Tk_SetWindowBorder ConfigWind Tk_SetWindowBorderPixmap ConfigWind Tk_SetWindowBorderWidth ConfigWind Tk_SetWindowColormap ConfigWind
	Tk_SetWindowVisual SetVisual Tk_SizeOfBitmap GetBitmap Tk_SizeOfImage GetImage Tk_StrictMotif StrictMotif
	Tk_TextLayoutToPostscript TextLayout Tk_TextWidth MeasureChar Tk_Uid GetUid Tk_UndefineCursor ConfigWind
	Tk_UnderlineChars MeasureChar Tk_UnderlineCharsInContext MeasureChar Tk_UnderlineTextLayout TextLayout Tk_Ungrab Grab
	Tk_UnmaintainGeometry MaintGeom Tk_UnmapWindow MapWindow Tk_UnsetGrid SetGrid Tk_UseWindow WinUtil
	Tk_Visual WindowId Tk_Width WindowId Tk_WindowId WindowId Tk_X WindowId
	Tk_Y WindowId
    }]

    # Tk-Befehl (auch Variablen-/Optionsseiten) -> Seite. Aus
    # man2markdown.tcl, Zweig tip-700, Stand 2026-10-25 (tkCmdFileMap,
    # dort aus den NAME-Abschnitten der Tk-Seiten erzeugt).
    variable tkCmdFileMap [dict create {*}{
	accessible accessible attribtable attribtable bell bell bind bind
	bindtags bindtags bitmap bitmap busy busy button button
	canvas canvas checkbutton checkbutton clipboard clipboard colors colors
	console console cursors cursors destroy destroy entry entry
	event event fileicon fileicon focus focus font font
	fontchooser fontchooser frame frame geometry tkvars grab grab
	grid grid image image keysyms keysyms label label
	labelframe labelframe listbox listbox lower lower menu menu
	menubutton menubutton message message nsimage nsimage option option
	options options pack pack panedwindow panedwindow photo photo
	place place print print radiobutton radiobutton raise raise
	safe::loadTk loadTk scale scale scrollbar scrollbar selection selection
	send send spinbox spinbox sysnotify sysnotify systray systray
	text text tk tk tk::mac tk_mac tk::scalingPct tkvars
	tk::svgFmt tkvars tk_bisque palette tk_chooseColor chooseColor tk_chooseDirectory chooseDirectory
	tk_dialog dialog tk_focusFollowsMouse focusNext tk_focusNext focusNext tk_focusPrev focusNext
	tk_getOpenFile getOpenFile tk_getSaveFile getOpenFile tk_library tkvars tk_menuSetFocus menu
	tk_messageBox messageBox tk_optionMenu optionMenu tk_patchLevel tkvars tk_popup popup
	tk_setPalette palette tk_strictMotif tkvars tk_textCopy text tk_textCut text
	tk_textPaste text tk_version tkvars tkerror tkerror tkwait tkwait
	toplevel toplevel ttk::button ttk_button ttk::checkbutton ttk_checkbutton ttk::combobox ttk_combobox
	ttk::entry ttk_entry ttk::frame ttk_frame ttk::intro ttk_intro ttk::label ttk_label
	ttk::labelframe ttk_labelframe ttk::menubutton ttk_menubutton ttk::notebook ttk_notebook ttk::panedwindow ttk_panedwindow
	ttk::progressbar ttk_progressbar ttk::radiobutton ttk_radiobutton ttk::scale ttk_scale ttk::scrollbar ttk_scrollbar
	ttk::separator ttk_separator ttk::sizegrip ttk_sizegrip ttk::spinbox ttk_spinbox ttk::style ttk_style
	ttk::toggleswitch ttk_toggleswitch ttk::treeview ttk_treeview ttk::widget ttk_widget ttk_image ttk_image
	ttk_vsapi ttk_vsapi winfo winfo wish wish wm wm
    }]

    # Tcl-Befehl -> Seite: erzeugt mit index aus den Tcl-Seiten des Zweigs
    # tip-700 (Stand 2026-10-25; Befehle der Uebersichten), dazu die
    # Zusatznamen von man2markdown (my next bgerror Tcl mathop mathfunc
    # tclvars tm msgcat tclsh). Ersetzt dessen Liste [info commands], die
    # vom laufenden tclsh abhing. Gebraucht fuer Seiten ausserhalb des
    # Tcl-Ordners (Tk); im Tcl-Ordner gilt dessen eigener Index.
    variable tclCmdFileMap [dict create {*}{
	oo::abstract abstract after after append append apply apply
	array array bgerror bgerror binary binary break break
	::tcl::build-info buildinfo callback callback mymethod callback catch catch
	cd cd chan chan oo::class class classvariable classvariable
	clock clock close close concat concat oo::configurable configurable
	oo::define define oo::objdefine define const const continue continue
	::http::cookiejar cookiejar oo::copy copy coroutine coroutine yield coroutine
	yieldto coroutine coroinject coroutine coroprobe coroutine dde dde
	oo::Slot define dict dict divmod divmod encoding encoding
	eof eof error error eval eval exec exec
	exit exit expr expr fblocked fblocked fconfigure fconfigure
	fcopy fcopy file file fileevent fileevent flush flush
	for for foreach foreach format format fpclassify fpclassify
	frexp frexp gets gets glob glob global global
	history history ::http::config http ::http::geturl http ::http::formatQuery http
	::http::quoteString http ::http::reset http ::http::wait http ::http::status http
	::http::size http ::http::error http ::http::postError http ::http::cleanup http
	::http::requestLine http ::http::requestHeaders http ::http::requestHeaderValue http ::http::responseLine http
	::http::responseCode http ::http::reasonPhrase http ::http::responseHeaders http ::http::responseHeaderValue http
	::http::responseInfo http ::http::responseBody http ::http::register http ::http::registerError http
	::http::unregister http ::http::code http ::http::data http ::http::meta http
	::http::metaValue http ::http::ncode http tcl::idna idna if if
	incr incr info info interp interp join join
	lappend lappend lassign lassign ledit ledit lfilter lfilter
	auto_execok library auto_import library auto_load library auto_mkindex library
	auto_qualify library auto_reset library tcl_findLibrary library parray library
	tcl_endOfWord library tcl_startOfNextWord library tcl_startOfPreviousWord library tcl_wordBreakAfter library
	tcl_wordBreakBefore library foreachLine library readFile library writeFile library
	lindex lindex link link linsert linsert list list
	llength llength lmap lmap load load lpop lpop
	lrange lrange lremove lremove lrepeat lrepeat lreplace lreplace
	lreverse lreverse lsearch lsearch lseq lseq lset lset
	lsort lsort ::tcl::mathfunc::abs mathfunc ::tcl::mathfunc::acos mathfunc ::tcl::mathfunc::acosh mathfunc
	::tcl::mathfunc::asin mathfunc ::tcl::mathfunc::atan mathfunc ::tcl::mathfunc::atan2 mathfunc ::tcl::mathfunc::bool mathfunc
	::tcl::mathfunc::cbrt mathfunc ::tcl::mathfunc::ceil mathfunc ::tcl::mathfunc::copysign mathfunc ::tcl::mathfunc::cos mathfunc
	::tcl::mathfunc::cosh mathfunc ::tcl::mathfunc::dim mathfunc ::tcl::mathfunc::double mathfunc ::tcl::mathfunc::entier mathfunc
	::tcl::mathfunc::erf mathfunc ::tcl::mathfunc::erfc mathfunc ::tcl::mathfunc::exp mathfunc ::tcl::mathfunc::exp2 mathfunc
	::tcl::mathfunc::expm1 mathfunc ::tcl::mathfunc::floor mathfunc ::tcl::mathfunc::fma mathfunc ::tcl::mathfunc::fmod mathfunc
	::tcl::mathfunc::hypot mathfunc ::tcl::mathfunc::int mathfunc ::tcl::mathfunc::isfinite mathfunc ::tcl::mathfunc::isinf mathfunc
	::tcl::mathfunc::isnan mathfunc ::tcl::mathfunc::isnormal mathfunc ::tcl::mathfunc::isqrt mathfunc ::tcl::mathfunc::issubnormal mathfunc
	::tcl::mathfunc::isunordered mathfunc ::tcl::mathfunc::lgamma mathfunc ::tcl::mathfunc::log mathfunc ::tcl::mathfunc::log10 mathfunc
	::tcl::mathfunc::log1p mathfunc ::tcl::mathfunc::log2 mathfunc ::tcl::mathfunc::logb mathfunc ::tcl::mathfunc::max mathfunc
	::tcl::mathfunc::min mathfunc ::tcl::mathfunc::nextafter mathfunc ::tcl::mathfunc::pow mathfunc ::tcl::mathfunc::rand mathfunc
	::tcl::mathfunc::remainder mathfunc ::tcl::mathfunc::round mathfunc ::tcl::mathfunc::signbit mathfunc ::tcl::mathfunc::sin mathfunc
	::tcl::mathfunc::sinh mathfunc ::tcl::mathfunc::sqrt mathfunc ::tcl::mathfunc::srand mathfunc ::tcl::mathfunc::tan mathfunc
	::tcl::mathfunc::tanh mathfunc ::tcl::mathfunc::gamma mathfunc ::tcl::mathfunc::trunc mathfunc ::tcl::mathfunc::wide mathfunc
	::tcl::mathop::! mathop ::tcl::mathop::~ mathop ::tcl::mathop::+ mathop ::tcl::mathop::- mathop
	::tcl::mathop::* mathop ::tcl::mathop::/ mathop ::tcl::mathop::% mathop ::tcl::mathop::** mathop
	::tcl::mathop::& mathop ::tcl::mathop::| mathop ::tcl::mathop::^ mathop ::tcl::mathop::<< mathop
	::tcl::mathop::>> mathop ::tcl::mathop::== mathop ::tcl::mathop::!= mathop ::tcl::mathop::< mathop
	::tcl::mathop::<= mathop ::tcl::mathop::>= mathop ::tcl::mathop::> mathop ::tcl::mathop::eq mathop
	::tcl::mathop::ne mathop ::tcl::mathop::lt mathop ::tcl::mathop::le mathop ::tcl::mathop::gt mathop
	::tcl::mathop::ge mathop ::tcl::mathop::in mathop ::tcl::mathop::ni mathop memory memory
	modf modf ::msgcat::mc msgcat ::msgcat::mcmax msgcat ::msgcat::mcexists msgcat
	::msgcat::mcpackagenamespaceget msgcat ::msgcat::mclocale msgcat ::msgcat::mcpreferences msgcat ::msgcat::mcloadedlocales msgcat
	::msgcat::mcload msgcat ::msgcat::mcset msgcat ::msgcat::mcmset msgcat ::msgcat::mcflset msgcat
	::msgcat::mcflmset msgcat ::msgcat::mcunknown msgcat ::msgcat::mcpackagelocale msgcat ::msgcat::mcpackageconfig msgcat
	::msgcat::mcforgetpackage msgcat ::msgcat::mcutil msgcat my my myclass my
	namespace namespace next next nextto next oo::object object
	open open package package ::pkg::create packagens pid pid
	pkg_mkIndex pkgMkIndex platform::generic platform platform::identify platform platform::patterns platform
	platform::shell::generic platform_shell platform::shell::identify platform_shell platform::shell::platform platform_shell ::tcl::prefix prefix
	proc proc ::tcl::process process puts puts pwd pwd
	read read regexp regexp registry registry tcl::registry registry
	regsub regsub remquo remquo rename rename return return
	::safe::interpCreate safe ::safe::interpInit safe ::safe::interpConfigure safe ::safe::interpDelete safe
	::safe::interpAddToAccessPath safe ::safe::interpFindInAccessPath safe ::safe::setSyncMode safe ::safe::setLogCmd safe
	scan scan seek seek self self set set
	oo::singleton singleton socket socket source source split split
	string string subst subst switch switch tailcall tailcall
	tclsh tclsh tcltest::test tcltest tcltest::loadTestedCommands tcltest tcltest::makeDirectory tcltest
	tcltest::removeDirectory tcltest tcltest::makeFile tcltest tcltest::removeFile tcltest tcltest::viewFile tcltest
	tcltest::cleanupTests tcltest tcltest::runAllTests tcltest tcltest::configure tcltest tcltest::customMatch tcltest
	tcltest::testConstraint tcltest tcltest::outputChannel tcltest tcltest::errorChannel tcltest tcltest::interpreter tcltest
	tcltest::debug tcltest tcltest::errorFile tcltest tcltest::limitConstraints tcltest tcltest::loadFile tcltest
	tcltest::loadScript tcltest tcltest::match tcltest tcltest::matchDirectories tcltest tcltest::matchFiles tcltest
	tcltest::outputFile tcltest tcltest::preserveCore tcltest tcltest::singleProcess tcltest tcltest::skip tcltest
	tcltest::skipDirectories tcltest tcltest::skipFiles tcltest tcltest::temporaryDirectory tcltest tcltest::testIterations tcltest
	tcltest::testsDirectory tcltest tcltest::verbose tcltest tcltest::normalizeMsg tcltest tcltest::normalizePath tcltest
	tcltest::workingDirectory tcltest tell tell throw throw time time
	timer timer timerate timerate ::tcl::tm::path tm ::tcl::tm::roots tm
	trace trace try try unicode unicode unknown unknown
	unload unload unset unset update update uplevel uplevel
	upvar upvar variable variable vwait vwait while while
	zipfs zipfs zlib zlib Tcl Tcl mathop mathop
	mathfunc mathfunc tclvars tclvars tm tm msgcat msgcat
    }]

    # Namen von Tcl-Seiten ohne Uebersicht (Themenseiten: Variablen in
    # tclvars, re_syntax, filename, Tcl) -> Seite; erzeugt wie
    # tclCmdFileMap (man2markdown verlinkt diese Namen nur auf einzelnen
    # Seiten, tclCmdListRemap).
    variable tclTopicFileMap [dict create {*}{
	Tcl Tcl filename filename re_syntax re_syntax argc tclvars
	argv tclvars argv0 tclvars auto_path tclvars env tclvars
	errorCode tclvars errorInfo tclvars tcl_interactive tclvars tcl_library tclvars
	tcl_patchLevel tclvars tcl_pkgPath tclvars tcl_platform tclvars tcl_rcFileName tclvars
	tcl_traceCompile tclvars tcl_traceExec tclvars tcl_version tclvars
    }]

    # Rueckgabecodes -> Seite. Aus man2markdown.tcl, Zweig tip-700, Stand
    # 2026-10-25 (tclReturnCodeFileMap).
    variable returnCodeFileMap [dict create {*}{
	TCL_OK catch TCL_ERROR catch TCL_RETURN catch TCL_BREAK catch TCL_CONTINUE catch
    }]

    # Seiten, auf denen bestimmte Woerter nicht verlinkt werden, weil sie
    # dort etwas anderes bedeuten (Schluessel: Dateiwurzel). Aus
    # man2markdown.tcl, Zweig tip-700, Stand 2026-10-25 (tclCmdListExclude;
    # dort aus tcltk-man2html.tcl uebernommen).
    variable cmdExclude [dict create {*}{
	bind		{button destroy option}
	clock		{next}
	canvas		{bitmap text}
	chan		{read}
	checkbutton	{image}
	cookiejar	{destroy configure info error set}
	console		{eval}
	clipboard	{string}
	define          {variable destroy}
	entry		{string}
	event		{return}
	expr            {variable}
	file            {socket}
	font		{menu}
	GetIndex        {option}
	getOpenFile	{file open text}
	grab		{global}
	history		{exec event}
	http 		{error Tcl binary text}
	info            {coroutine proc}
	interp		{time}
	library         {text}
	menu		{checkbutton radiobutton}
	messageBox	{error info}
	namespace       {text}
	next		{unknown destroy}
	options		{bitmap image set}
	radiobutton	{image}
	regexp          {binary}
	re_syntax       {lower print}
	safe		{join split}
	scale		{label variable}
	scrollbar	{set}
	selection	{string}
	string          {lower print}
	tcltest		{error Tcl}
	tclvars         {Tcl split}
	text		{bind image lower raise}
	timerate        {lindex}
	tkvars		{tk}
	tkwait		{variable}
	tm		{exec}
	trace           {variable rename unset read}
	transchan       {read}
	try             {error return break continue}
	zlib		{binary close filename text time}
	ttk_checkbutton	{variable}
	ttk_combobox	{selection}
	ttk_entry	{focus variable}
	ttk_intro	{focus text}
	ttk_label	{font text}
	ttk_labelframe	{text}
	ttk_menubutton	{flush}
	ttk_notebook	{image text}
	ttk_progressbar	{variable}
	ttk_radiobutton	{variable}
	ttk_scale	{variable}
	ttk_scrollbar	{set}
	ttk_spinbox	{format}
	ttk_treeview	{text open focus selection}
	ttk_widget	{image text variable}
	TclZlib		{binary flush filename text time}
    }]
}

# ============================================================
# Hilfen
# ============================================================

proc n2md::tip700::_d {d k {def ""}} {
    # kein expr: das machte aus dem Text "2.10" die Zahl 2.1
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}

# Argumente einer Makrozeile wie nroff: "..." (Anfuehrung, auch leer) oder Wort
proc n2md::tip700::_args {rest} {
    set out {}
    foreach {- q w} [regexp -all -inline {"([^"]*)"?|(\S+)} $rest] {
        if {$w ne ""} { lappend out $w } else { lappend out $q }
    }
    return $out
}

# Argumente nach parseArgs von man2markdown: ab Spalte 4, an einzelnen
# Leerzeichen getrennt, "..." als ein Argument (".IP \(bu 3" -> \(bu 3)
proc n2md::tip700::_macroArgs {line} {
    return [_args [string range $line 4 end]]
}

# Zweites Wort einer Kommentarzeile (".\" METHOD: x" -> METHOD:)
proc n2md::tip700::_commentWord {line} {
    set w [regexp -all -inline {\S+} $line]
    return [lindex $w 1]
}

# Schriftwechsel entfernen (man2markdown: BIRPstrip)
proc n2md::tip700::_strip {text} {
    return [string map {\\fB {} \\fI {} \\fR {} \\fP {}} $text]
}

# nroff-Escapes -> Zeichen (man2markdown: parseBackslash, dazu weitere
# Zeichennamen; unbekannte bleiben stehen). Nicht-ASCII als \u.
proc n2md::tip700::_backslash {text} {
    if {[string first \\ $text] < 0} { return $text }
    return [string map [list \
        \\e \\ \
        \\- - \
        \\N'34' \" \
        \\(en \u2013 \
        \\(em \u2014 \
        \\(-> \u2192 \
        \\(<- \u2190 \
        \\\\ \\ \
        \\| {} \
        \\^ {} \
        \\0 { } \
        "\\ " { } \
        \\~ { } \
        \\& {} \
        \\% {} \
        \\c {} \
        \\: {} \
        \\/ {} \
        \\, {} \
        \\(fm ' \
        \\(aq ' \
        \\(dq \" \
        \\(lq \" \
        \\(rq \" \
        \\(oq ' \
        \\(cq ' \
        \\(ga ` \
        \\(ha ^ \
        \\(ti ~ \
        \\(bu \u2022 \
        \\(co \u00a9 \
        \\(rg \u00ae \
        \\(de \u00b0 \
        \\(mu \u00d7 \
        \\(<= \u2264 \
        \\(>= \u2265 \
        \\(!= \u2260 \
        \\(+- \u00b1 \
        \\(^o \u00f4 \
        \\(mc \u00b5 \
        \\(*m \u00b5 \
        \\` ` \
        \\' ' \
        \\. . \
        {*}[_glyphs] \
    ] $text]
}

# groff-Zeichennamen \(xx (Latin-1 und einige Sonderzeichen, keysyms.n)
# -> Zeichen. Stehen hinter den Eintraegen von _backslash, die bei
# gleichem Namen (\(co, \(mu ...) vorgehen.
proc n2md::tip700::_glyphs {} {
    variable glyphMap
    if {[info exists glyphMap]} { return $glyphMap }
    set glyphMap {}
    foreach {n c} {
        r! ¡ ct ¢ Po £ Cs ¤ Ye ¥ bb ¦ sc §
        ad ¨ Of ª Fo « no ¬ a- ¯ S2 ² S3 ³
        aa ´ ps ¶ pc · ac ¸ S1 ¹ Om º Fc »
        14 ¼ 12 ½ 34 ¾ r? ¿
        `A À 'A Á ^A Â ~A Ã :A Ä oA Å AE Æ ,C Ç
        `E È 'E É ^E Ê :E Ë `I Ì 'I Í ^I Î :I Ï
        -D Ð ~N Ñ `O Ò 'O Ó ^O Ô ~O Õ :O Ö
        /O Ø `U Ù 'U Ú ^U Û :U Ü 'Y Ý TP Þ ss ß
        `a à 'a á ^a â ~a ã :a ä oa å ae æ ,c ç
        `e è 'e é ^e ê :e ë `i ì 'i í ^i î :i ï
        Sd ð ~n ñ `o ò 'o ó ~o õ :o ö di ÷
        /o ø `u ù 'u ú ^u û :u ü 'y ý Tp þ :y ÿ
        eu € mi - ul _ bv | br │
    } {
        lappend glyphMap "\\($n" $c
    }
    return $glyphMap
}

# Text fuer YAML-Kopf und Ueberschriften: Escapes aufgeloest, ohne Schrift
proc n2md::tip700::_plain {s} {
    set s [string map {{\(co} "(c)"} $s]
    return [string trim [_backslash [_strip $s]]]
}

# YAML-Wert ohne Anfuehrung wie man2markdown, ausser er wuerde sonst
# falsch gelesen (": " im Wert, fuehrendes Sonderzeichen)
proc n2md::tip700::_yval {s} {
    if {[regexp {: |^[-?:,\[\]{}#&*!|>'"%@`]| #|:$} $s]} {
        return "\"[string map {\\ \\\\ \" \\\"} $s]\""
    }
    return $s
}

# Markdown-Escapes fuer Text (man2markdown, AST2Markdown_Element Text):
# * \ _ [ ] -- sonst nichts
proc n2md::tip700::_esc {s} {
    return [string map {* \\* \\ \\\\ _ \\_ [ \\[ ] \\]} $s]
}

# ============================================================
# Vorverarbeitung: Makrodefinitionen, Bedingungen, Schriftmakros
# ============================================================

# nroff-Anweisungen ohne Inhalt fuer Markdown
namespace eval n2md::tip700 {
    variable dropMacros {
        nr ds as rm rr ad na hy nh ne in ti ft ps vs ll lt pl bp wh ev
        mk rt ns rs tr cs ss so lf cc c2 ec eo hw pc tm ch dt it em fl
        pn po ul cu uf IX PD UC AT Sp Vb Ve ig ie el if
    }
}

proc n2md::tip700::_fontMacro {macro rest} {
    set a [_args [string trim $rest]]
    if {![llength $a]} { return "" }
    set m [string range $macro 1 end]
    switch -- $m {
        B - SB { return "\\fB[join $a { }]\\fR" }
        I      { return "\\fI[join $a { }]\\fR" }
        R - SM { return [join $a " "] }
    }
    set fonts [split $m ""]
    set out ""
    set k 0
    foreach x $a {
        append out "\\f[lindex $fonts [expr {$k % 2}]]$x"
        incr k
    }
    return "$out\\fR"
}

proc n2md::tip700::_prep {text} {
    variable dropMacros
    set text [string map {"\r\n" "\n" "\r" "\n"} $text]
    set out {}
    set inDef 0
    set brace 0
    set nextFont ""
    foreach line [split $text \n] {
        # .de/.am/.ig ... ..
        if {$inDef} {
            if {[regexp {^\.\.\s*$} $line]} { set inDef 0 }
            continue
        }
        if {[regexp {^[.']\s*(de|de1|am|ig)(\s|$)} $line]} { set inDef 1; continue }
        # Bedingungsbloecke ".if ... \{" bis "\}"
        if {$brace > 0} {
            incr brace [expr {[regexp -all {\\\{} $line] - [regexp -all {\\\}} $line]}]
            if {$brace < 0} { set brace 0 }
            continue
        }
        # Kommentare bleiben (Copyright, METHOD:)
        if {[regexp {^[.']\\"} $line]} {
            lappend out $line
            continue
        }
        if {[regexp {^[.']\s*([A-Za-z0-9]{1,3})(\s|$)} $line -> m]} {
            if {$m in $dropMacros} {
                if {$m in {if ie el}} {
                    set brace [expr {[regexp -all {\\\{} $line] - [regexp -all {\\\}} $line]}]
                    if {$brace < 0} { set brace 0 }
                }
                continue
            }
        }
        if {[regexp {^[.']\s*\\\}} $line]} continue
        # "'" als Steuerzeichen (ausser Kommentar): nicht Text. Folgt kein
        # Anweisungsname, ist es Text (keysyms.n im Code: "' (apostrophe)
        # 39 0x27"; nroff verschluckt die Zeile, gemeint ist sie als Text)
        if {[string index $line 0] eq "'" && [regexp {^'\s*[A-Za-z]} $line]} continue
        # Inline-Kommentar \" am Zeilenende
        if {[string first \\\" $line] >= 0} {
            regsub {(^|[^\\])\\".*$} $line {\1} line
        }
        # Zeichenketten \*(xx und \*x
        if {[string first \\* $line] >= 0} {
            set line [string map {\\*(lq \" \\*(rq \" \\*(qu \" \\*(Tm (TM) \\*(R (R)} $line]
            regsub -all {\\\*(\([A-Za-z0-9]{2}|\[[^\]]*\]|[A-Za-z0-9])} $line {} line
        }
        # Schriften \f1 \f2 \f3 \f(CW ...
        if {[regexp {\\f[123(\[C]} $line]} {
            set line [string map {\\f1 \\fR \\f2 \\fI \\f3 \\fB \\f(CW \\fB \\f(CB \\fB \\f(CI \\fI \\f[] \\fR \\f[B] \\fB \\f[I] \\fI \\f[R] \\fR \\fC \\fB} $line]
        }
        # Schriftmakros .B .I .BR ...
        if {[regexp {^\.(B|I|R|BI|IB|BR|RB|IR|RI|SB|SM)(\s.*)?$} $line -> m rest]} {
            set t [_fontMacro .$m $rest]
            if {$t eq ""} { set nextFont [string index $m 0]; continue }
            set line $t
        } elseif {$nextFont ne "" && ![string match .* $line] && [string trim $line] ne ""} {
            set line "\\f$nextFont$line\\fR"
            set nextFont ""
        }
        # Makro mit Satzzeichen ohne Leerzeichen dahinter (doctools,
        # diagram.n ".IP, etc\&. is"): Makro und Textzeile
        if {[regexp {^(\.(?:IP|PP|LP|TP|RS|RE|CS|CE|br|sp))([,.;:!?)].*)$} $line -> mac rest]} {
            lappend out $mac $rest
            continue
        }
        # Leerzeichen am Zeilenende bleiben (man2markdown: "value.  This"
        # ueber zwei Zeilen)
        lappend out $line
    }
    return [_optTables $out]
}

# doctools schreibt Widget-Optionen als Tabelle (ctext.n, ipentry.n,
# widgetPlus.n):
#   .LP / .nf / .ta 6c / Command-Line Switch:<Tab>\fB-x\fR /
#   Database Name:<Tab>\fBx\fR / Database Class:<Tab>\fBX\fR / / .fi / .IP
# Daraus ".OP -x x X" wie in den Tk-Seiten: Begriff und Definition
proc n2md::tip700::_optTables {lines} {
    if {[lsearch -regexp $lines {^Command-Line Switch:}] < 0} { return $lines }
    set out {}
    set n [llength $lines]
    for {set k 0} {$k < $n} {incr k} {
        set l [lindex $lines $k]
        if {$l eq ".nf"} {
            set j [expr {$k + 1}]
            if {[string match .ta* [lindex $lines $j]]} { incr j }
            set vals {}
            foreach key {{Command-Line Switch} {Database Name} {Database Class}} {
                if {[regexp "^$key:\\s*(.*)\$" [lindex $lines $j] -> v]} {
                    lappend vals [string trim [_strip $v]]
                    incr j
                }
            }
            while {$j < $n && [string trim [lindex $lines $j]] eq ""} { incr j }
            if {[llength $vals] == 3 && [lindex $vals 0] ne "" && [lindex $lines $j] eq ".fi"} {
                # .LP/.PP davor gehoert zur Tabelle
                if {[lindex $out end] in {.LP .PP}} { set out [lrange $out 0 end-1] }
                lassign $vals sw dn dc
                lappend out ".OP \"$sw\" \"$dn\" \"$dc\""
                set k $j
                continue
            }
        }
        lappend out $l
    }
    return $out
}

# ============================================================
# Kopf: .TH, Copyright, Links, Keywords
# ============================================================

proc n2md::tip700::_th {lines} {
    foreach l $lines {
        if {[regexp {^\.TH\s+(.*)$} $l -> rest]} {
            return [_thArgs $rest]
        }
    }
    return {}
}

# .TH-Argumente; ein Name aus zwei Woertern ohne Anfuehrung (".TH tk print
# n \"\" Tk ...", print.n, sysnotify.n, systray.n in Tk 9.0) wird ein Name:
# sonst waere "print" der Abschnitt und die Seite fiele in die Gruppe Tcl
proc n2md::tip700::_thArgs {rest} {
    set a [_args $rest]
    if {[llength $a] > 5 && ![regexp {^([0-9][A-Za-z]*|[nlop])$} [lindex $a 1]]} {
        set a [lreplace $a 0 1 "[lindex $a 0] [lindex $a 1]"]
    }
    return $a
}

# ============================================================
# Inline: \fB/\fI aufraeumen und zerlegen
# ============================================================

# man2markdown BIRPclean: Leerraum aus Fett/Kursiv nach aussen, \fP wie
# \fR. Statt Fehler bei schmutziger Auszeichnung ("\fR" ohne \fB,
# "\fB" nach \fB) wird die Marke uebergangen.
proc n2md::tip700::_birp {text} {
    if {[string first \\f $text] < 0} { return $text }
    set text [string map {{\fB \fI} {\fR \fI} {\fI \fB} {\fR \fB}} $text]
    set state N
    set out ""
    set n [string length $text]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $text $i]
        if {$c ne "\\"} { append out $c; continue }
        set la [string range $text [expr {$i + 1}] [expr {$i + 2}]]
        if {[string index $la 0] eq "\\"} {
            # "\\" (Backslash) nicht als Anfang von \fB lesen
            append out "\\\\"
            incr i
            continue
        }
        if {$la ni {fB fI fR fP}} { append out $c; continue }
        set lf [string index $text [expr {$i + 3}]]
        set lb [string index $text [expr {$i - 1}]]
        set lb2 [string range $text [expr {$i - 2}] [expr {$i - 1}]]
        # Leerzeichen vor der Marke schon nach aussen gezogen (" \fR" hinter
        # "\fI \fB"): dann steht es in out, nicht mehr vor der Marke
        if {$lb eq " " && [string index $out end] ne " "} { set lb "" }
        if {$lb2 eq " ?" && [string range $out end-1 end] ne " ?"} { set lb2 "" }
        # leere Schrift ("\fBconcat\fI \fR?", "\fIarg\fB \fR..."): die
        # gerade geoeffnete Marke faellt weg statt "\fI\fR"
        if {$state in {B I} && $la in {fR fP}
                && [string range $out end-2 end] in [list "\\fB" "\\fI"]} {
            set out [string range $out 0 end-3]
            set state N
            incr i 2
            continue
        }
        switch -- $state {
            N {
                # Leerzeichen gleich nach der Marke nach aussen
                # ("their\fB destroy\fR" -> "their **destroy**", singleton.n)
                set sp ""
                if {$lf eq " " && $la in {fB fI}} {
                    if {[string index $out end] ne " "} { set sp " " }
                    incr i
                }
                switch -- $la {
                    fB { append out $sp \\fB; set state B }
                    fI { append out $sp \\fI; set state I }
                }
            }
            B {
                switch -- $la {
                    fR - fP {
                        if {$lb eq " "} {
                            set out [string range $out 0 end-1]
                            append out \\fR " "
                        } else {
                            append out \\fR
                        }
                        set state N
                    }
                    fI {
                        if {$lb eq " "} {
                            set out [string range $out 0 end-1]
                            append out \\fR " "
                        } elseif {$lb2 eq " ?"} {
                            set out [string range $out 0 end-2]
                            append out \\fR " ?"
                        } else {
                            append out \\fR
                        }
                        if {$lf eq " "} { append out " "; incr i }
                        append out \\fI
                        set state I
                    }
                }
            }
            I {
                switch -- $la {
                    fB {
                        if {$lb eq " "} {
                            set out [string range $out 0 end-1]
                            append out \\fR " "
                        } else {
                            append out \\fR
                        }
                        if {$lf eq " "} { append out " "; incr i }
                        append out \\fB
                        set state B
                    }
                    fR - fP {
                        if {$lb eq " "} {
                            set out [string range $out 0 end-1]
                            append out \\fR " "
                        } else {
                            append out \\fR
                        }
                        set state N
                    }
                }
            }
        }
        incr i 2
    }
    return $out
}

# Rohtext (nach _birp) -> Inline-Knoten {Typ Attribute Inhalt}
#   Text Strong Emphasis Quoted Span
# Quoted: \x01"..."\x01 (.QW), Span mit Version: \x02info:...\x03 (.VS)
proc n2md::tip700::_inlines {content} {
    variable Q
    variable VS
    variable VE
    set out {}
    while {$content ne ""} {
        set c [string index $content 0]
        set la [string range $content 1 2]
        if {$c eq "\\" && $la in {fB fI fR fP}} {
            if {$la in {fR fP}} {
                set content [string range $content 3 end]
                continue
            }
            set kw [expr {$la eq "fB" ? "Strong" : "Emphasis"}]
            if {[regexp -indices -start 3 {\\f[BIRP]} $content m]} {
                set e [lindex $m 0]
                set inner [string range $content 3 [expr {$e - 1}]]
                if {[string index $content [expr {$e + 2}]] in {R P}} {
                    set content [string range $content [expr {$e + 3}] end]
                } else {
                    set content [string range $content $e end]
                }
            } else {
                set inner [string range $content 3 end]
                set content ""
            }
            if {$inner ne ""} {
                if {[lindex $out end 0] eq $kw} {
                    # gleiche Schrift direkt dahinter ("\fIe1\fR\fIe2\fR",
                    # pt_peg_introduction.n): ein Lauf, sonst "*e1**e2*"
                    lset out end 2 [concat [lindex $out end 2] [_inlines $inner]]
                } else {
                    lappend out [list $kw {} [_inlines $inner]]
                }
            }
        } elseif {$c eq $Q && [string index $content 1] eq "\""} {
            set e [string first "\"$Q" $content 2]
            if {$e < 0} {
                set content [string range $content 1 end]
                continue
            }
            lappend out [list Quoted {} [_inlines [string range $content 2 [expr {$e - 1}]]]]
            set content [string range $content [expr {$e + 2}] end]
        } elseif {$c eq $VS} {
            set ie [string first : $content 1]
            if {$ie < 0} { set ie 0 }
            set info [string range $content 1 [expr {$ie - 1}]]
            set e [string first $VE $content [expr {$ie + 1}]]
            if {$e < 0} { set e [string length $content] }
            set inner [string trim [string range $content [expr {$ie + 1}] [expr {$e - 1}]]]
            if {$inner ne ""} {
                lappend out [list Span [list -vs $info] [_inlines $inner]]
            }
            set content [string range $content [expr {$e + 1}] end]
        } else {
            if {[regexp -indices "\\\\f\[BIRP\]|$Q\"|$VS" $content m]} {
                set e [lindex $m 0]
                if {$e == 0} {
                    # einzelne Marke ohne Gegenstueck
                    set e 1
                }
            } else {
                set e [string length $content]
            }
            set t [string range $content 0 [expr {$e - 1}]]
            set t [string map [list $VE "" $Q ""] $t]
            lappend out [list Text {} [_backslash $t]]
            set content [string range $content $e end]
        }
    }
    return $out
}

# nroff-Text -> Inline-Knoten
proc n2md::tip700::_inline {text} {
    return [_inlines [_birp [_spaces $text]]]
}

# Leerzeichen-Escapes (\0 "\ " \~) vor _birp aufloesen, damit es sie als
# Leerraum aus Fett/Kursiv herausnimmt: "\fB<\0\fIfileName\fR" (exec.n)
# -> "**<** *fileName*"
proc n2md::tip700::_spaces {text} {
    if {[string first \\ $text] < 0} { return $text }
    return [string map [list "\\\\" "\\\\" "\\0" " " "\\ " " " "\\~" " "] $text]
}

# .QW/.PQ/.QR -> Rohtext mit Anfuehrungsmarken (man2markdown parseQuoting)
proc n2md::tip700::_quoting {line} {
    variable Q
    set type [string range $line 1 2]
    lassign [_macroArgs $line] a1 a2 a3
    set t ""
    if {$type eq "PQ"} { set t "(" }
    append t $Q\" $a1
    if {$type eq "QR"} {
        append t - $a2 \"$Q
    } else {
        append t \"$Q $a2
    }
    if {$type eq "PQ"} { append t ")" }
    append t $a3
    return $t
}

# ============================================================
# Uebersicht: eine Befehlszeile -> Spans (man2markdown parseCommand)
# ============================================================
#
# Marken nach _birp: \fB -> B, \fI -> I, \fR -> R (hier als \x11 \x12 \x13
# statt "\u00a7 + =" von man2markdown, damit "+" im Text bleibt). Alle Muster
# wie dort; was dort mit "exit" endet, wird hier Text.

namespace eval n2md::tip700 {
    variable mB \x11
    variable mI \x12
    variable mR \x13
}

# Span-Knoten mit reinem Text
proc n2md::tip700::_sp {cls text} {
    return [list Span $cls [list [list Text {} $text]]]
}

proc n2md::tip700::_unmark {w} {
    variable mB; variable mI; variable mR
    return [string map [list $mB "" $mI "" $mR ""] $w]
}

# Zeile -> Liste von Inline-Knoten (Span/Space/Text/Strong)
#   ver  - Version aus .VS fuer den Befehl (version="...")
#   cApi - Seite aus Abschnitt 3
proc n2md::tip700::_command {line {ver ""} {cApi 0}} {
    variable mB; variable mI; variable mR
    set va [expr {$ver ne "" ? [list -vs $ver] : {}}]
    set line [_birp $line]
    set line [string map [list \\fB $mB \\fI $mI \\fR $mR \\fP $mR] $line]
    # Abstaende ohne Zeichen (\| \^ \& \%): "\-\|\-" ist "--" (dde.n)
    set line [string map {\\| {} \\^ {} \\& {} \\% {}} $line]
    set line [string map {\\ {}} $line]
    set B $mB; set I $mI; set R $mR

    # Abschnitt 3: "#typ <B>name<R>(args)" bzw. "typedef typ <B>name<R>(args)"
    if {[regexp "^typedef (.*?)$B" $line -> rt]} {
        set s [string first $B $line]
        set p [string first ( $line $s]
        if {$p > 0} {
            set words [list "#typedef [string trim $rt]" \
                [string range $line $s [expr {$p - 1}]] \
                [string range $line [expr {$p + 1}] end-1]]
            return [_cmdWords $words $va 1]
        }
    } elseif {[regexp {^.+\(.*\);?$} $line]} {
        set line [string trimright $line ";"]
        set s 0
        set l0 ""
        if {[string index $line 0] eq "#"} {
            set s [string first $B $line]
            if {$s < 0} { set s 0 }
            set l0 [string trim [string range $line 0 [expr {$s - 1}]]]
        }
        set p [string first ( $line $s]
        set l1 [string range $line $s [expr {$p - 1}]]
        set l2 [string range $line [expr {$p + 1}] end-1]
        # nur ein Bezeichner vor "(" ist eine Funktion
        if {[regexp "^$B?\[A-Za-z_\]\[A-Za-z0-9_:\]*$R?\$" [string trim $l1]]} {
            set words [expr {$l0 eq "" ? [list $l1 $l2] : [list $l0 $l1 $l2]}]
            return [_cmdWords $words $va 1]
        }
    } elseif {[string index $line 0] eq $B && [string index $line 1] eq "#"} {
        # "#include <tcl.h>"
        return [list [list Strong {} [list [list Text {} [string trim [_unmark $line]]]]]]
    }
    if {$cApi && [string index $line 0] eq "#"} {
        # Rueckgabetyp ohne Funktion danach
        return [list [list Text {} [string range [_unmark $line] 1 end]]]
    }
    # Woerter; zwei Gruppen ohne Leerzeichen ("?+??script?", bind.n)
    # werden getrennt, Klammern { } sind eigene Woerter (switch.n)
    set words {}
    foreach w [regexp -all -inline {\S+} $line] {
        while {[regexp "^(\\?\[^?\]*$R?\\?)(\\?.+)\$" $w -> a b] && [string length $a] > 2} {
            lappend words $a
            set w $b
        }
        # Klammern um eine Gruppe von Alternativen (doctools: "(\fIlocal\fR |
        # -data \fIdata\fR)", "(?\fIoptions\fR? \fIfile\fR)\&.\&.\&.",
        # ftp.n, fileutil.n): eigene Woerter, ohne Leerzeichen ausgegeben
        # (Marken \x15 auf, \x16 zu), damit das Wort darin erkannt wird
        set zu ""
        if {[string length $w] > 1 && [string index $w 0] eq "("} {
            lappend words "\x15("
            set w [string range $w 1 end]
        }
        # ")" nur ohne "(" im Wort ("value(s)", photo.n, bleibt ein Wort)
        if {[string length $w] > 1 && [string first ( $w] < 0
                && [regexp {^(.+?)(\)(?:\.\.\.)?)$} $w -> w zu]} {
            set zu "\x16$zu"
        }
        lappend words $w
        if {$zu ne ""} { lappend words $zu }
    }
    # Gruppe in Klammern ueber mehrere Woerter ("{keyVariable valueVariable}",
    # array.n, dict.n, photo.n "-format {format-name ?option value ...?}")
    # ist ein Argument: ein Wort, das _cmdWords als .arg ausgibt
    set merged {}
    set n [llength $words]
    for {set k 0} {$k < $n} {incr k} {
        set w [lindex $words $k]
        set u [_unmark $w]
        if {[string index $u 0] eq "\{" && [_braceDepth $u] > 0} {
            set g $w
            set d [_braceDepth $u]
            set j $k
            while {$d > 0 && $j + 1 < $n} {
                incr j
                append g " " [lindex $words $j]
                set d [_braceDepth [_unmark $g]]
            }
            # ohne schliessende Klammer (configurable.n: "oo::define class" und
            # Klammer allein am Zeilenende):
            # einzelne Woerter wie bisher
            if {$d == 0} {
                lappend merged $g
                set k $j
                continue
            }
        }
        lappend merged $w
    }
    return [_cmdWords $merged $va 0]
}

# Zeichenkette fuer einen regulaeren Ausdruck schuetzen
proc n2md::tip700::_reQuote {s} {
    return [regsub -all {[][\\^$.|?*+(){}]} $s {\\&}]
}

# Tiefe offener { } in einem Wort
proc n2md::tip700::_braceDepth {s} {
    return [expr {[regexp -all {\{} $s] - [regexp -all {\}} $s]}]
}

# Wort ist eine Klammergruppe aus mehreren Woertern ({a b})
proc n2md::tip700::_isBraceGroup {w} {
    set u [_unmark $w]
    return [expr {[string index $u 0] eq "\{" && [string index $u end] eq "\}"
        && [string first " " $u] > 0 && [_braceDepth $u] == 0}]
}

# Woerter -> Spans (Kern von parseCommand)
proc n2md::tip700::_cmdWords {words va cfun} {
    variable mB; variable mI; variable mR
    set B $mB; set I $mI; set R $mR
    set out {}
    set n [llength $words]
    set cmdType ""
    set i 0
    while {$i < $n} {
        set w [lindex $words $i]
        if {$i == 0} {
            if {[regexp "^$B-.+$R\$" $w]} {
                lappend out [_sp .lit [string range $w 1 end-1]]
            } elseif {[regexp "^$B-\[^$R\]+\$" $w] && $i + 1 < $n
                    && [_isBraceGroup [lindex $words [expr {$i + 1}]]]} {
                # Option vor einer Klammergruppe, fett bis in die Klammer
                # ("\fB\-format {\fIformat-name\fR ...}", photo.n)
                lappend out [_sp .lit [_unmark $w]]
            } elseif {[regexp "^$B\[|<>2\].*$R" $w]} {
                lappend out [_sp .lit [_unmark $w]]
            } elseif {[regexp "^$B.+$R\$" $w]} {
                set name [string range $w 1 end-1]
                if {$cfun} {
                    set cmdType ccmd
                } else {
                    set cmdType cmd
                }
                lappend out [_sp [concat .$cmdType $va] [_unmark $name]]
            } elseif {[regexp "^$B\[^$R\]+\$" $w]} {
                # Befehl mit Unterbefehl, weitere fette Woerter .lit
                lappend out [_sp [concat .cmd $va] [_unmark [string range $w 1 end]]]
                set k 1
                while {$i + 1 < $n} {
                    # Klammergruppe beendet die fetten Woerter (array.n
                    # "\fBarray for {\fIkeyVariable valueVariable\fB}")
                    if {[_isBraceGroup [lindex $words [expr {$i + 1}]]]} break
                    incr i
                    set w [lindex $words $i]
                    set t [expr {$k == 1 ? ".sub" : ".lit"}]
                    incr k
                    if {[string index $w end] eq $R} {
                        lappend out {Space {} {}} [_sp $t [_unmark $w]]
                        break
                    }
                    lappend out {Space {} {}} [_sp $t [_unmark $w]]
                }
            } elseif {[regexp "^$I.+$R\$" $w]} {
                # Instanz als Befehl (pathName cget)
                lappend out [_sp .ins [_unmark $w]]
                if {$i + 1 < $n && [string index [lindex $words [expr {$i + 1}]] 0] ne "?"} {
                    incr i
                    set w [lindex $words $i]
                    lappend out {Space {} {}} [_sp .sub [_unmark $w]]
                    # weitere fette Woerter ("\fBscan mark\fR", canvas.n): .lit
                    if {[string index $w 0] eq $B && [string index $w end] ne $R} {
                        while {$i + 1 < $n} {
                            incr i
                            set w [lindex $words $i]
                            lappend out {Space {} {}} [_sp .lit [_unmark $w]]
                            if {[string index $w end] eq $R} break
                        }
                    }
                }
            } elseif {[string index $w 0] eq "#"} {
                # Rueckgabetyp (Abschnitt 3)
                lappend out [_sp .ret [_unmark [string range $w 1 end]]] {Space {} {}}
                set words [lrange $words 1 end]
                incr n -1
                continue
            } elseif {[regexp "^$I" $w]} {
                # kursiv ohne Ende im Wort: ".ins" bis zum Ende
                lappend out [_sp .ins [_unmark $w]]
            } else {
                # nicht erkannt (man2markdown: exit): Text
                lappend out [list Text {} [_unmark $w]]
            }
            incr i
            continue
        }
        if {$cmdType eq "ccmd"} {
            lappend out {Space {} {}} [_sp .cargs [string trim [_unmark $w]]]
            incr i
            continue
        }
        if {[string index $w 0] in {\x15 \x16}} {
            # Klammer einer Gruppe (_command): Text, das Leerzeichen danach
            # bzw. davor faellt weg (unten)
            lappend out {Space {} {}} [list Text {} $w]
            incr i
            continue
        }
        # doctools: Option ohne Schrift in einer optionalen Gruppe
        # ("?-format \fIformat\fR?", crc16.n, graph.n, htmlparse.n) wie
        # "?\fB-format\fR \fIformat\fR?": [[-format]{.lit} [format]{.arg}]{.optarg}
        if {[regexp {^\?(-[^?\x11\x12\x13]+)$} $w -> opt] && $i + 1 < $n
                && [string index [lindex $words [expr {$i + 1}]] 0] eq $I} {
            set w "?$B$opt$R"
        }
        # Klammergruppe {a b ...}: ein Argument
        if {[_isBraceGroup $w]} {
            lappend out {Space {} {}} [_sp .arg [_unmark $w]]
        } elseif {[regexp "^\\?$I.+ \\.\\.\\.$R\\?\$" $w]} {
            lappend out {Space {} {}} [_sp .optdot [_unmark [string range $w 2 end-5]]]
        } elseif {[regexp "^$I\\?(\[^?\]+?)(\\.\\.\\.)?\\?$R\$" $w -> inner dots]} {
            # Fragezeichen in der Schrift (doctools "\fI?processname?\fR",
            # cron.n; "\fI?field\&.\&.\&.?\fR"): optional wie "?\fIx\fR?"
            lappend out {Space {} {}} [_sp [expr {$dots ne "" ? ".optdot" : ".optarg"}] $inner]
        } elseif {[regexp "^$I.+$R\$" $w]} {
            lappend out {Space {} {}} [_sp .arg [_unmark $w]]
        } elseif {[regexp "^$I.+" $w]} {
            # mehrere kursive Woerter: je ein .arg, bis eines mit Ende
            lappend out {Space {} {}} [_sp .arg [_unmark $w]]
            while {$i + 1 < $n} {
                set nw [lindex $words [expr {$i + 1}]]
                if {[string match {\?*} $nw] || [regexp "^\[$B$I\x15\x16\]" $nw]} break
                incr i
                # Satzzeichen nach dem Ende der Schrift ("\fIx y\fR.",
                # listbox.n) bleibt ausserhalb
                if {[regexp "^(.*$R)(\[.,;:\]+)\$" $nw -> nw punkt]} {
                    lappend out {Space {} {}} [_sp .arg [_unmark $nw]] [list Text {} $punkt]
                    break
                }
                lappend out {Space {} {}} [_sp .arg [_unmark $nw]]
                if {[string index $nw end] eq $R} break
            }
        } elseif {[regexp "^\\?$I.+$R\\?\$" $w]} {
            lappend out {Space {} {}} [_sp .optarg [_unmark [string range $w 1 end-1]]]
        } elseif {[regexp "^$B.+$R\$" $w]} {
            lappend out {Space {} {}} [_sp .lit [_unmark $w]]
        } elseif {[regexp "^\\?$B.+$R\\?\$" $w]} {
            lappend out {Space {} {}} [_sp .optlit [_unmark [string range $w 1 end-1]]]
        } elseif {[regexp "^\\?$B.+$R\$" $w]} {
            # Gruppe ?-option wert?: erstes .lit, dann .arg
            set sub [list [_sp .lit [_unmark [string range $w 1 end]]]]
            set gt .optarg
            while {$i + 1 < $n} {
                incr i
                set w [lindex $words $i]
                if {[regexp "^\\?$I.+$R\\?\\?\$" $w]} {
                    # verschachtelt: ?-frame ?bool?? (interp.n)
                    lappend sub {Space {} {}} [_sp .optarg [_unmark [string range $w 1 end-2]]]
                    break
                } elseif {[string index $w 0] eq $I} {
                    if {[string index $w end] eq "?"} {
                        lappend sub {Space {} {}} [_sp .arg [_unmark [string range $w 0 end-1]]]
                        break
                    }
                    lappend sub {Space {} {}} [_sp .arg [_unmark $w]]
                } elseif {[regexp "^\\?$B?(-\[^?$B$I$R\]+)$R?\$" $w -> opt] && $i + 1 < $n
                        && [string index [lindex $words [expr {$i + 1}]] 0] eq $I} {
                    # innere Gruppe ?-opt arg? (graph.n "?-key \fIkey\fR ?-value
                    # \fIvalue\fR??", mime.n): eigene .optarg; "??" schliesst
                    # auch die aeussere
                    set sub2 [list [_sp .lit $opt]]
                    set ende 0
                    while {$i + 1 < $n} {
                        incr i
                        set w [lindex $words $i]
                        set u [_unmark $w]
                        if {[string range $u end-1 end] eq "??"} {
                            lappend sub2 {Space {} {}} [_sp .arg [string range $u 0 end-2]]
                            set ende 1
                            break
                        } elseif {[string index $u end] eq "?"} {
                            lappend sub2 {Space {} {}} [_sp .arg [string range $u 0 end-1]]
                            break
                        }
                        lappend sub2 {Space {} {}} [_sp .arg $u]
                    }
                    lappend sub {Space {} {}} [list Span .optarg $sub2]
                    if {$ende} break
                } elseif {[string range $w 0 2] eq "..."} {
                    set gt .optdot
                    break
                } else {
                    # anderes Muster in der Gruppe (man2markdown: Fehler)
                    set t [string trimright [_unmark $w] ?]
                    # "?" allein schliesst die Gruppe ("\fIscript... \fR?")
                    if {$t ne ""} { lappend sub {Space {} {}} [list Text {} $t] }
                    if {[string index $w end] eq "?"} break
                }
            }
            lappend out {Space {} {}} [list Span $gt $sub]
        } elseif {[regexp "^\\?(\[$I$B\])\[^$R\]" $w -> font] && [string index $w end] ne "?"} {
            # mehrere optionale Woerter ?a b ...? (fett: .optlit, wm.n
            # "?\fBoption value option value...\fR?")
            set content [list [_unmark [string range $w 1 end]]]
            set t [expr {$font eq $B ? ".optlit" : ".optarg"}]
            while {$i + 1 < $n} {
                incr i
                set w [lindex $words $i]
                if {[regexp {\?\.\.\.$} $w] && $t eq ".optarg"} {
                    # "?\fIkey\fR \fIvalue\fR?\&.\&.\&." (uri.n): Gruppe wiederholt
                    set rest [string range [_unmark $w] 0 end-4]
                    if {$rest ne ""} { lappend content $rest }
                    set t .optdot
                    break
                }
                if {[string range $w end-1 end] eq "$R?" || [string index $w end] eq "?"} {
                    set w [string trimright [_unmark $w] ?]
                    if {$w eq "..." && $t eq ".optarg"} {
                        set t .optdot
                    } else {
                        lappend content $w
                    }
                    break
                }
                lappend content [_unmark $w]
            }
            lappend out {Space {} {}} [_sp $t [string trim [join $content " "]]]
        } elseif {[regexp {^\?.+\?$} $w]} {
            # ?wort? ohne Schrift (doctools: "?key?")
            lappend out {Space {} {}} [_sp .optarg [_unmark [string range $w 1 end-1]]]
        } elseif {[regexp "^$B\[^$R\]+\$" $w] && $i + 1 < $n} {
            # mehrere fette Woerter ("\fBdataCmd\fR \fBmove start\fR",
            # canvas_epoints.n): je ein .lit wie ein einzelnes fettes Wort
            lappend out {Space {} {}} [_sp .lit [_unmark $w]]
            while {$i + 1 < $n} {
                # Klammergruppe oder Kursives beendet die fetten Woerter
                # ("\fBscript {\fIkeyVariable valueVariable\fB} \fIscript",
                # dict.n)
                set nw [lindex $words [expr {$i + 1}]]
                if {[_isBraceGroup $nw] || [string index $nw 0] in [list $I ? \x15 \x16]} break
                incr i
                set w $nw
                if {[_unmark $w] eq "..."} {
                    # "\fBelseif ...\fR" (if.n): Auslassung als Text
                    lappend out {Space {} {}} [list Text {} ...]
                } else {
                    lappend out {Space {} {}} [_sp .lit [_unmark $w]]
                }
                if {[string index $w end] eq $R} break
            }
        } elseif {$cmdType eq "cmd" && [regexp {^[A-Za-z][-A-Za-z0-9_.]*$} $w]
                && [lindex $out end 1 0] in {.cmd .lit}
                && [llength $out] == 2 * $i - 1} {
            # Wort ohne Schrift gleich nach dem Befehl (doctools: "\fB$widget\fR
            # topic \fIcommand\fR", chatwidget.n): .lit wie ein fettes Wort
            lappend out {Space {} {}} [_sp .lit $w]
        } else {
            lappend out {Space {} {}} [list Text {} [_unmark $w]]
        }
        incr i
    }
    # Klammern: kein Leerzeichen nach "(" und vor ")"
    set res {}
    set weg 0
    foreach x $out {
        if {$weg && [lindex $x 0] eq "Space"} { set weg 0; continue }
        set weg 0
        if {[lindex $x 0] eq "Text" && [string index [lindex $x 2] 0] eq "\x16"} {
            if {[lindex $res end 0] eq "Space"} { set res [lrange $res 0 end-1] }
            lappend res [list Text {} [string range [lindex $x 2] 1 end]]
            continue
        }
        if {[lindex $x 0] eq "Text" && [string index [lindex $x 2] 0] eq "\x15"} {
            lappend res [list Text {} [string range [lindex $x 2] 1 end]]
            set weg 1
            continue
        }
        lappend res $x
    }
    return $res
}

# ============================================================
# Bloecke (man2markdown parseBlock)
# ============================================================
#
# Knoten {Typ Attribute Inhalt}:
#   Header    {-level n}          Text (fertig, ohne Escapes)
#   Paragraph {} / {DISPLAY yes}  Rohtext (nroff, mit Marken)
#   Code      {}                  Text
#   Dlist     {}                  DlistItem-Knoten
#   DlistItem {-definition roh ?-vs v? ?-cmd 1?}  Bloecke
#   List      {-type bullet|numbered}             ListItem-Knoten
#   ListItem  {}                  Bloecke
#   Div       Klasse              Bloecke
#   Syntax    {}                  Inline-Knoten (fertig)
#   Inlines   {}                  Inline-Knoten (fertig, als Absatz)

# Makroname einer Zeile (".TP 15" -> .TP); "" fuer Text
proc n2md::tip700::_macro {line} {
    if {[regexp {^[.']\\"} $line]} { return {.\"} }
    if {[regexp {^\.([A-Za-z0-9]+)} $line -> m]} { return .$m }
    if {[string trim $line] eq "."} { return . }
    return ""
}

# Zeilen -> Bloecke. top: oberste Ebene (Abschnitte, Kopf)
proc n2md::tip700::_blocks {lines {top 0}} {
    variable P
    variable VS
    variable VE
    set blocks {}
    set type ""
    set content ""
    set attrs {}
    set vsOpen 0
    set pendingVs ""
    set n [llength $lines]
    set i 0
    # Block schliessen; m: das Makro, das ihn schliesst
    set close {
        if {$content ne ""} {
            set pendingVs ""
            if {$vsOpen} {
                append content $VE
                set vsOpen 0
                # offene .VS-Region laeuft in die folgende Liste weiter
                # (info.n: "-scope" mit .IP public/unexported/private)
                if {$m in {.TP .IP .OP}} { set pendingVs $vsInfo }
            }
            if {[regexp "$VS\(\[^:\]*\):$VE\$" $content -> tv]} {
                set content [string trimright [regsub "$VS\[^:\]*:$VE\$" $content ""]]
                if {$m in {.TP .IP .OP}} { set pendingVs $tv }
            }
            if {[string trim [regsub -all "$VS\[^:\]*:|$VE" $content ""]] ne ""} {
                lappend blocks [list $type $attrs $content]
            }
        } else {
            set pendingVs ""
        }
        set type ""; set content ""; set attrs {}; set plines 0
    }
    set plines 0
    while {$i < $n} {
        set line [lindex $lines $i]
        set m [_macro $line]
        switch -- $m {
            {.\"} {
                dict set P lastComment [_commentWord $line]
                incr i
            }
            .RS {
                # Zeile mit Option allein und eingerueckter Erklaerung
                # (".br \fB\-tabposition\fP \fIposition\fP .RS ... .RE",
                # Styling options der ttk-Seiten): Begriff und Definition
                if {$type eq "Paragraph" && $plines == 1 && ![llength $attrs]
                        && [regexp {^\\fB(\\-|-)} $content]} {
                    set r [_rsBlock $lines $i]
                    set term $content
                    set type ""; set content ""; set plines 0
                    set b [_blocks [lindex $r 0]]
                    if {![llength $b]} { set b [_blocks {{see below ...}}] }
                    lappend blocks [list Dlist {} [list [list DlistItem [list -definition [_birp $term]] $b]]]
                    set i [lindex $r 1]
                    continue
                }
                # .RS bricht wie in nroff die Zeile: neuer Absatz (nicht,
                # wenn erst ".VS" darin steht, msgcat.n ".PP .VS TIP499 .RS")
                if {$type eq "Paragraph" && ![llength $attrs]
                        && [string trim [regsub -all "$VS\[^:\]*:|$VE" $content ""]] ne ""} { eval $close }
                incr i
            }
            .RE {
                if {$type eq "Paragraph" && ![llength $attrs]
                        && [string trim [regsub -all "$VS\[^:\]*:|$VE" $content ""]] ne ""} { eval $close }
                incr i
            }
            .BS - .BE - .AS - .ta - .sp - .AE - .SE - .UE - .ns - .ft - .fi {
                if {$m eq ".fi" && $type eq "Code" && [_d $attrs nf 0]} {
                    eval $close
                }
                # .sp im Inhalt eines Eintrags: neuer Absatz (doctools schreibt
                # [para] in Listen so, ntextIndent.n); man2markdown uebergeht
                # .sp, auf oberster Ebene bleibt das so
                if {$m eq ".sp" && !$top && $type eq "Paragraph" && ![llength $attrs]
                        && [string trim [regsub -all "$VS\[^:\]*:|$VE" $content ""]] ne ""} {
                    eval $close
                }
                incr i
            }
            .nf {
                # .nf ausserhalb von SYNOPSIS/CLASS HIERARCHY: vorformatiert
                # (man2markdown uebergeht .nf; im Kern kommt das nicht vor)
                if {$type ne "Code"} {
                    if {$type ne ""} { eval $close }
                    set type Code
                    set attrs {nf 1}
                }
                incr i
            }
            .TH {
                incr i
            }
            .TP - .IP - .OP {
                if {$type ne ""} { eval $close; continue }
                # .IP ohne Marke im Inhalt eines Eintrags: eingerueckter
                # Absatz (doctools, tklib/tcllib), keine Liste mit leerem
                # Begriff. Auf oberster Ebene wie man2markdown (FontId.3)
                if {!$top && $m eq ".IP" && [_ipTag $line] eq ""} {
                    set type Paragraph
                    incr i
                    continue
                }
                set r [_list $lines $i $pendingVs $top]
                set pendingVs ""
                lappend blocks [lindex $r 0]
                set i [lindex $r 1]
            }
            .AP {
                if {$type ne ""} { eval $close; continue }
                set r [_arguments $lines $i]
                lappend blocks {*}[lindex $r 0]
                set i [lindex $r 1]
            }
            .SH {
                dict set P lastComment ""
                dict set P lastCmdWord ""
                if {$type ne ""} { eval $close; continue }
                set r [_section $lines $i]
                lappend blocks {*}[lindex $r 0]
                set i [lindex $r 1]
            }
            .SS {
                dict set P lastComment ""
                dict set P lastCmdWord ""
                if {$type ne ""} { eval $close; continue }
                set t [_heading [string range $line 3 end]]
                dict lappend P sectionTitles $t
                lappend blocks [list Header {-level 2} $t]
                incr i
            }
            .PP - .LP - .P - . - .br {
                if {$type ne ""} { eval $close; continue }
                set type Paragraph
                incr i
            }
            .CS - .TS - .PS {
                # .PS/.PE (Bild, tcllib pt_astree.n): als Code
                if {$type ne ""} { eval $close; continue }
                set type Code
                incr i
            }
            .CE - .DE - .TE - .PE {
                eval $close
                incr i
            }
            .QW - .PQ - .QR {
                if {$type eq ""} { set type Paragraph }
                if {$type eq "Code"} {
                    set t [string map [list $::n2md::tip700::Q ""] [_quoting $line]]
                    append content [expr {$content eq "" ? "" : "\n"}] $t
                } else {
                    append content [expr {$content eq "" ? "" : " "}] [_quoting $line]
                }
                incr i
            }
            .MT {
                if {$type eq ""} { set type Paragraph }
                append content [expr {$content eq "" ? "" : " "}] {""}
                incr i
            }
            .VS {
                if {$type eq "Code"} { incr i; continue }
                if {$type eq ""} { set type Paragraph }
                set info [lindex [_macroArgs $line] 0]
                append content [expr {$content eq "" ? "" : " "}] "$VS$info:"
                set vsOpen 1
                set vsInfo $info
                incr i
            }
            .VE {
                if {$vsOpen} {
                    append content $VE
                    set vsOpen 0
                }
                incr i
            }
            .DS {
                if {$type ne ""} { eval $close; continue }
                set type Paragraph
                set attrs {DISPLAY yes}
                incr i
            }
            .SO {
                # Standardoptionen (Tk): Liste der Optionen als Absatz
                if {$type ne ""} { eval $close; continue }
                set r [_stdOptions $lines $i]
                set sb [lindex $r 0]
                # zweites .SO gleich danach (ttk_spinbox.n: ttk_widget, dann
                # ttk_entry): derselbe Abschnitt, keine zweite Ueberschrift
                if {[llength $blocks] && [lindex $blocks end] eq [_d $P lastStdOpt ""]} {
                    set sb [lrange $sb 1 end]
                }
                dict set P lastStdOpt [lindex $sb end]
                lappend blocks {*}$sb
                set i [lindex $r 1]
            }
            .UL {
                if {$type eq ""} { set type Paragraph }
                set a [_macroArgs $line]
                append content [expr {$content eq "" ? "" : " "}] "\\fI[lindex $a 0]\\fR[lindex $a 1]"
                incr i
            }
            "" {
                # wie man2markdown: Zeilen im Code mit "\n", sonst mit " "
                # (auch Leerzeilen; am Anfang eines Blocks fallen sie weg)
                if {$type eq ""} { set type Paragraph }
                # "\&.nf"/"\&.fi" im Bild (.PS) sind keine Zeilen
                if {$type eq "Code" && [regexp {^\\&\.(nf|fi)\s*$} $line]} {
                    incr i
                    continue
                }
                incr plines
                if {$content eq ""} {
                    set content $line
                } else {
                    # .DS (Tabelle mit .ta): Zeilen bleiben Zeilen; man2markdown
                    # klebt sie zu einer (bind.n: Modifikatoren, Ereignisarten)
                    append content [expr {$type eq "Code" || [dict exists $attrs DISPLAY] ? "\n" : " "}] $line
                }
                incr i
            }
            default {
                # unbekanntes Makro: uebergehen
                incr i
            }
        }
    }
    set m ""
    if {$content ne ""} {
        if {$vsOpen} { append content $VE }
        if {[string trim [regsub -all "$VS\[^:\]*:|$VE" $content ""]] ne ""} {
            lappend blocks [list $type $attrs $content]
        }
    }
    return $blocks
}

# Zeilen von .RS (Index i) bis zum passenden .RE -> {Zeilen neuerIndex};
# innere .RS/.RE bleiben in den Zeilen
proc n2md::tip700::_rsBlock {lines i} {
    set n [llength $lines]
    set depth 0
    set out {}
    while {$i < $n} {
        set l [lindex $lines $i]
        set m [_macro $l]
        if {$m eq ".RS"} {
            if {$depth > 0} { lappend out $l }
            incr depth
        } elseif {$m eq ".RE"} {
            incr depth -1
            if {$depth == 0} { incr i; break }
            lappend out $l
        } elseif {$m in {.SH .SS}} {
            break
        } else {
            lappend out $l
        }
        incr i
    }
    return [list $out $i]
}

# .SH-Ueberschrift -> Text. Woerter in Grossbuchstaben bekommen die
# Schreibweise, die sie im Text der Seite haben ("TCL_DSTRING" ->
# "Tcl_DString", "TYPENAME" -> "typeName", "API" bleibt), sonst klein;
# Woerter mit Kleinbuchstaben bleiben ("REs"). Gaengige Abkuerzungen
# (API, URL, UTF ...) bleiben gross, wenn der Text keine Form vorgibt. Der erste Buchstabe gross,
# wenn das erste Wort klein wurde. man2markdown: string totitle (alles
# klein) und Korrekturen je Seite.
proc n2md::tip700::_heading {raw} {
    variable P
    set t [_plain [string trim [string trim $raw] "\" "]]
    set forms [_d $P wordForms {}]
    set out ""
    set first 1
    set firstLower 0
    foreach {all word sep} [regexp -all -inline {([A-Za-z0-9_]+)|([^A-Za-z0-9_]+)} $t] {
        if {$word eq ""} {
            append out $sep
            continue
        }
        set w $word
        if {$w eq "I"} {
            # Pronomen (snitfaq.n "HOW CAN I ..."): bleibt gross
        } elseif {[regexp {[A-Z]} $w] && ![regexp {[a-z]} $w]} {
            set k [string tolower $w]
            if {[dict exists $forms $k]} {
                set w [_bestForm [dict get $forms $k]]
            } elseif {$k ni {api ansi ascii dde gui html http https id ip ipv4 ipv6
                    json mime posix rfc smtp ssl tcp tls udp uri url utf xml}} {
                set w $k
            }
        }
        if {$first} {
            set firstLower [expr {![regexp {[A-Z]} $w]}]
            set first 0
        }
        append out $w
    }
    if {$firstLower} {
        set out "[string toupper [string index $out 0]][string range $out 1 end]"
    }
    return $out
}

proc n2md::tip700::_bestForm {counts} {
    set best ""
    set bn -1
    foreach {f c} $counts {
        if {$c > $bn || ($c == $bn && $f eq [string tolower $f])} {
            set best $f
            set bn $c
        }
    }
    return $best
}

# Schreibweisen der Woerter im Text (fuer _heading): Zaehler je Form.
# "Gross am Anfang" (Errors) zaehlt nur mitten im Satz.
proc n2md::tip700::_wordForms {lines} {
    set forms {}
    # Verweise auf Abschnitte ("see \fBHIGH RESOLUTION TIMERS\fR") zaehlen nicht
    set titel {}
    foreach l $lines {
        if {[regexp {^\.S[HS]\s+(.*)$} $l -> t]} {
            set t [_plain [string trim [string trim $t] "\" "]]
            if {[regexp {[A-Z]} $t]} { lappend titel $t "" }
        }
    }
    foreach l $lines {
        if {[string match .* $l] || [string match '* $l]} continue
        set l [string map $titel [_strip $l]]
        foreach r [regexp -all -inline -indices {[A-Za-z][A-Za-z0-9_]*} $l] {
            set w [string range $l {*}$r]
            if {[string length $w] < 2} continue
            if {[regexp {^[A-Z][a-z0-9_]*$} $w]} {
                set vor [string trimright [string range $l 0 [expr {[lindex $r 0] - 1}]]]
                if {$vor eq "" || [regexp {[.!?:]$} $vor]} continue
            }
            set k [string tolower $w]
            set c [_d $forms $k {}]
            dict set c $w [expr {[_d $c $w 0] + 1}]
            dict set forms $k $c
        }
    }
    return $forms
}

# .SH: Abschnitt; SEE ALSO/KEYWORDS in den Kopf, SYNOPSIS, ARGUMENTS,
# CLASS HIERARCHY besonders. -> {Bloecke neuerIndex}
proc n2md::tip700::_section {lines i} {
    variable P
    set line [lindex $lines $i]
    set raw [string trim [string trim [string range $line 3 end]] "\" "]
    set key [string toupper [_plain $raw]]
    set n [llength $lines]
    incr i
    if {$key in {"SEE ALSO" KEYWORDS}} {
        # Abschnitt mit Listen oder Absaetzen statt einer Wortliste
        # (tcllib tool.n: ".SH KEYWORDS" mit .TP-Eintraegen fuer die
        # Schluesselwoerter von tool::define, danach erst die echte
        # Wortliste): ein gewoehnlicher Abschnitt
        for {set k $i} {$k < $n} {incr k} {
            set m [_macro [lindex $lines $k]]
            if {$m in {.SH .SS}} break
            if {$m in {.TP .IP .PP .LP .P .RS .CS .nf .DS .OP .AP}} {
                set key ""
                break
            }
        }
    }
    if {$key eq "ARGUMENTS"} {
        # nur mit .AP die Argumentliste der C-Schnittstelle; sonst (tcllib
        # tepam_doc_gen.n, mapproj.n: .TP-Liste) ein gewoehnlicher
        # Abschnitt, die Liste lief als ein Absatz zusammen
        set ap 0
        for {set k $i} {$k < $n} {incr k} {
            set m [_macro [lindex $lines $k]]
            if {$m in {.SH .SS}} break
            if {$m eq ".AP"} { set ap 1; break }
        }
        if {!$ap} { set key "" }
    }
    switch -- $key {
        "SEE ALSO" - KEYWORDS {
            set words {}
            set txt ""
            while {$i < $n} {
                set l [lindex $lines $i]
                set m [_macro $l]
                if {$m in {.SH .SS}} break
                if {$m in {.QW .PQ .QR}} {
                    set l [string map [list $::n2md::tip700::Q ""] [_quoting $l]]
                } elseif {$m ne ""} {
                    incr i
                    continue
                }
                append txt " " $l
                incr i
            }
            foreach w [split $txt ,] {
                set w [string trim [regsub -all {\s+} [_plain $w] " "]]
                # "lsort(n) string(n)" ohne Komma (lappend.n)
                if {[regexp {^\S+\(\w+\)( \S+\(\w+\))+$} $w]} {
                    lappend words {*}[split $w " "]
                } elseif {$w ne ""} {
                    lappend words $w
                }
            }
            set meta [dict get $P meta]
            lappend meta [expr {$key eq "KEYWORDS" ? "Keywords" : "Links"}] $words
            dict set P meta $meta
            return [list {} $i]
        }
        SYNOPSIS {
            set t [_heading $raw]
            dict lappend P sectionTitles $t
            return [_synopsis $lines $i $t]
        }
        ARGUMENTS {
            set t [_heading $raw]
            dict lappend P sectionTitles $t
            set r [_arguments $lines $i 1]
            return [list [concat [list [list Header {-level 1} $t]] [lindex $r 0]] [lindex $r 1]]
        }
        "CLASS HIERARCHY" {
            set t [_heading $raw]
            dict lappend P sectionTitles $t
            set code {}
            set in 0
            while {$i < $n} {
                set l [lindex $lines $i]
                set m [_macro $l]
                if {$m eq ".SH"} break
                incr i
                if {$m eq ".nf"} { set in 1; continue }
                if {$m eq ".fi"} break
                if {$m ne ""} continue
                lappend code $l
            }
            set b [list [list Header {-level 1} $t]]
            if {[llength $code]} {
                lappend b [list Div .classhierarchy [list [list Code {} [join $code \n]]]]
            }
            return [list $b $i]
        }
        default {
            set t [_heading $raw]
            dict lappend P sectionTitles $t
            return [list [list [list Header {-level 1} $t]] $i]
        }
    }
}

# SYNOPSIS: jede Zeile eine Befehlszeile (Syntax); Zeilen, die nicht so
# aussehen, bleiben Absatz (Tcl.n "Summary of Tcl language syntax.",
# libexpect.man)
proc n2md::tip700::_synopsis {lines i title} {
    variable P
    set n [llength $lines]
    set cApi [expr {[dict get $P section] eq "3"}]
    set ver ""
    set syn {}
    set out [list [list Header {-level 1} $title]]
    set prosa ""
    set prosaAbs {}
    set nachher {}
    # Abschnitt 3 mit .nf: nur dort stehen Prototypen, Text ausserhalb
    # bleibt Text (libexpect.man)
    set hasNf 0
    for {set k $i} {$k < $n} {incr k} {
        set m [_macro [lindex $lines $k]]
        if {$m eq ".SH"} break
        if {$m eq ".nf"} { set hasNf 1; break }
    }
    # Abschnitt 3, Zeile ganz fett (alter Stil, libexpect.man: ".B int",
    # ".B exp_spawnv(file,argv);"): nur der Funktionsname bleibt fett,
    # Argumente kursiv; dann gilt dieselbe Regel wie fuer Tcl/Tk
    if {$cApi && $hasNf} {
        set nf 0
        for {set k $i} {$k < $n} {incr k} {
            set l [lindex $lines $k]
            set m [_macro $l]
            if {$m eq ".SH"} break
            if {$m eq ".nf"} { set nf 1 } elseif {$m eq ".fi"} { set nf 0 }
            if {$nf && [regexp {^\\fB([^\\#][^\\]*)\\f[RP]$} $l -> inner]} {
                if {[regexp {^(.*?)([A-Za-z_][A-Za-z0-9_]*)\((.*)\)(;?)$} $inner -> pre name argl semi]
                        && ![regexp {\($} $pre]} {
                    set l "$pre\\fB$name\\fR(\\fI$argl\\fR)$semi"
                } else {
                    set l $inner
                }
                lset lines $k $l
            }
        }
    }
    set inNf 0
    while {$i < $n} {
        set l [lindex $lines $i]
        set m [_macro $l]
        if {$m in {.SH}} break
        incr i
        if {$m eq ".nf"} { set inNf 1; continue }
        if {$m eq ".fi"} { set inNf 0; continue }
        # (ausserhalb .nf doch ein Prototyp: Sleep.3 hat ".fi" statt ".sp")
        if {$cApi && (!$hasNf || !$inNf)
                && !($hasNf && [regexp {^\\fB[A-Za-z_][A-Za-z0-9_]*\\f[RP]\(} $l])} {
            if {$m eq ""} { append prosa " " $l } elseif {$m in {.QW .PQ .QR}} { append prosa " " [_quoting $l] }
            continue
        }
        if {$m eq ".VS"} { set ver [lindex [_macroArgs $l] 0]; continue }
        if {$m eq ".VE"} { set ver ""; continue }
        if {$m in {.QW .PQ .QR}} {
            append prosa " " [_quoting $l]
            continue
        }
        if {$m eq ".SO"} {
            # Tk 8.6: Standardoptionen in der Uebersicht
            set r [_stdOptions $lines [expr {$i - 1}]]
            lappend nachher {*}[lindex $r 0]
            set i [lindex $r 1]
            continue
        }
        if {$m in {.sp .PP .LP .P .br} && [string trim $prosa] ne ""} {
            # Text ausserhalb der Uebersicht: .sp trennt Absaetze (doctools
            # clay.n, tool.n: "proc \fBclay::PROC\fR ..." je Zeile)
            lappend prosaAbs [string trim $prosa]
            set prosa ""
            continue
        }
        if {$m ne ""} continue
        set s [string trim $l]
        if {$s eq ""} {
            # Leerzeile: leere Zeile im Block (link.n)
            lappend syn [list Syntax {} {}]
            continue
        }
        # Prosa: beginnt nicht mit Schrift, ?, # oder "package require"
        set isSyn [regexp {^(\\f[BI]|\?|\\&?\\f|#|package require|typedef )} $s]
        if {$cApi && !$isSyn} {
            # Rueckgabetyp allein auf der Zeile, Funktion in der naechsten
            if {![string match {*\\fB*} $l] && $i < $n
                    && [string match {*\\fB*} [lindex $lines $i]]
                    && [_macro [lindex $lines $i]] eq ""} {
                set l "#$l [lindex $lines $i]"
                incr i
                set isSyn 1
            } elseif {[regexp {^[A-Za-z_][A-Za-z0-9_ *]*$} $s]} {
                set isSyn 1
            }
        }
        if {!$isSyn && ![llength $syn]} {
            append prosa " " $l
            continue
        }
        if {!$isSyn} {
            append prosa " " $l
            continue
        }
        if {[string match {package require *} $s]} {
            lappend syn [list Syntax {} [_pkgRequire $s]]
            continue
        }
        # Fortsetzung mit "\" am Zeilenende (FindPhoto.3)
        while {[string index $l end] eq "\\" && [string index $l end-1] ne "\\" && $i < $n} {
            set l "[string range $l 0 end-1] [string trim [lindex $lines $i]]"
            incr i
        }
        lappend syn [list Syntax {} [_command $l $ver $cApi]]
    }
    set leer 1
    foreach x $syn { if {[lindex $x 2] ne ""} { set leer 0 } }
    if {!$leer} {
        lappend out [list Div .synopsis $syn]
    }
    if {[string trim $prosa] ne ""} {
        lappend prosaAbs [string trim $prosa]
    }
    foreach a $prosaAbs {
        lappend out [list Paragraph {} $a]
    }
    lappend out {*}$nachher
    return [list $out $i]
}

# doctools: "package require \fBbase64 ?2\&.6\&.1?\fR"
proc n2md::tip700::_pkgRequire {s} {
    set w [regexp -all -inline {\S+} [_backslash [_strip $s]]]
    set out [list [_sp .cmd [lindex $w 0]] {Space {} {}} [_sp .sub [lindex $w 1]]]
    set opt ""
    foreach x [lrange $w 2 end] {
        if {$opt ne ""} {
            # "?8.5 9?" ueber mehrere Woerter (mapproj.n): ein .optlit
            append opt " " $x
            if {[string index $x end] eq "?"} {
                lappend out {Space {} {}} [_sp .optlit [string range $opt 1 end-1]]
                set opt ""
            }
        } elseif {[regexp {^\?(.+)\?$} $x -> v]} {
            lappend out {Space {} {}} [_sp .optlit $v]
        } elseif {[string index $x 0] eq "?"} {
            set opt $x
        } else {
            lappend out {Space {} {}} [_sp .lit $x]
        }
    }
    if {$opt ne ""} { lappend out {Space {} {}} [_sp .lit $opt] }
    return $out
}

# .AP-Eintraege (ARGUMENTS) -> Definitionsliste
#   [*statPtr]{.carg .out type="struct stat"}
#   : Erklaerung
# div: im Abschnitt ARGUMENTS in "::: {.arguments} :::"
proc n2md::tip700::_arguments {lines i {div 0}} {
    set n [llength $lines]
    set items {}
    set argName ""
    set runs {}
    set curVer ""
    set curText {}
    set vor {}
    while {$i < $n} {
        set l [lindex $lines $i]
        set m [_macro $l]
        if {$m in {.SH .SS}} break
        if {!$div && $m in {.TP .IP .PP .LP .CS .OP}} break
        if {$m eq ".AP"} {
            if {$argName ne ""} {
                if {[llength $curText]} { lappend runs [list $curVer $curText] }
                lappend items [_cargItem $argType $argName $argDir $runs]
            }
            lassign [_macroArgs $l] argType argName argDir
            if {$argDir eq ""} { set argDir inout }
            set runs {}
            set curVer ""
            set curText {}
        } elseif {$m eq ".VS"} {
            if {[llength $curText]} { lappend runs [list $curVer $curText]; set curText {} }
            set curVer [lindex [_macroArgs $l] 0]
        } elseif {$m eq ".VE"} {
            if {[llength $curText]} { lappend runs [list $curVer $curText]; set curText {} }
            set curVer ""
        } elseif {$m in {.QW .PQ .QR}} {
            lappend curText [_quoting $l]
        } elseif {$m eq ""} {
            if {$argName eq ""} {
                lappend vor $l
            } else {
                lappend curText $l
            }
        }
        incr i
    }
    if {$argName ne ""} {
        if {[llength $curText]} { lappend runs [list $curVer $curText] }
        lappend items [_cargItem $argType $argName $argDir $runs]
    }
    set out {}
    if {[string trim [join $vor " "]] ne ""} {
        lappend out [list Paragraph {} [string trim [join $vor " "]]]
    }
    if {[llength $items]} {
        if {$div} {
            lappend out [list Div .arguments [list [list Dlist {} $items]]]
        } else {
            lappend out [list Dlist {} $items]
        }
    }
    return [list $out $i]
}

proc n2md::tip700::_cargItem {type name dir runs} {
    set term [list Span [list .carg .$dir "type=\"[_plain $type]\""] \
        [list [list Text {} [_backslash $name]]]]
    set expl {}
    foreach run $runs {
        lassign $run v ls
        set t [string trim [join $ls " "]]
        if {$t eq ""} continue
        if {[llength $expl]} { lappend expl {Space {} {}} }
        if {$v ne ""} {
            lappend expl [list Span [list -vs $v] [_inline $t]]
        } else {
            lappend expl {*}[_inline $t]
        }
    }
    return [list DlistItem [list -inlines [list $term]] [list [list Inlines {} $expl]]]
}

# .SO ?seite? ... .SE (Tk): wie die Makros in man.macros eine Ueberschrift
# "STANDARD OPTIONS", die Optionen und "See the options manual entry for
# details on the standard options." -> {Bloecke neuerIndex}
proc n2md::tip700::_stdOptions {lines i} {
    variable P
    set n [llength $lines]
    set seite [lindex [_macroArgs [lindex $lines $i]] 0]
    if {$seite eq ""} { set seite options }
    set opts {}
    incr i
    while {$i < $n} {
        set l [lindex $lines $i]
        set m [_macro $l]
        if {$m in {.SE .SH .SS}} {
            if {$m eq ".SE"} { incr i }
            break
        }
        incr i
        if {$m ne ""} continue
        foreach o [split $l \t] {
            set o [string trim $o]
            if {$o ne ""} { lappend opts "\\fB$o\\fR" }
        }
    }
    set t [_heading "STANDARD OPTIONS"]
    dict lappend P sectionTitles $t
    set out [list [list Header {-level 1} $t]]
    if {[llength $opts]} {
        lappend out [list Paragraph {} [join $opts ", "]]
    }
    lappend out [list Paragraph {} "See the \\fB$seite\\fR manual entry for details on the standard options."]
    return [list $out $i]
}

# .TP/.IP/.OP-Liste ab Zeile i -> {Knoten neuerIndex}
# Wie man2markdown: .RS/.RE klammern weitere Absaetze, Listen und Code
# eines Eintrags; .PP/.LP ausserhalb davon oder .SH/.SS beenden die
# Liste. Anders als dort zaehlt .RS/.RE die Tiefe (innere .RS/.RE
# gehen an den Inhalt des Eintrags), und Eintraege ohne Begriff gehen
# nicht verloren.
proc n2md::tip700::_list {lines i pendingVs {top 0}} {
    variable P
    set n [llength $lines]
    set line [lindex $lines $i]
    set m [_macro $line]
    set blockType Dlist
    set lattrs {}
    if {$m eq ".IP"} {
        # wie man2markdown "[1]" "(1)" "1)" und "\(bu", dazu mehrstellig
        # und "\0\(bu" (ttk_entry.n)
        set num [lindex [_macroArgs $line] 0]
        regsub {^(\\0|\\&|\\ )+} $num "" num
        if {[regexp {^(\[[0-9]+\]|\([0-9]+\)|[0-9]+\))$} $num]} {
            set blockType List
            set lattrs {-type numbered}
        } elseif {$num eq "\\(bu"} {
            set blockType List
            set lattrs {-type bullet}
        }
    }
    set items {}
    set itemNum ""
    set title ""
    set titleVs ""
    set isCmd 0
    set haveItem 0
    set content {}
    set dlistVs $pendingVs
    set depth 0
    while {$i < $n} {
        set line [lindex $lines $i]
        set m [_macro $line]
        set fertig 0
        switch -- $m {
            .RS {
                if {$depth > 0} { lappend content $line }
                incr depth
            }
            .RE {
                if {$depth > 1} { lappend content $line }
                if {$depth == 1} {
                    # Ende der eingerueckten Bloecke des Eintrags: als Marke
                    # im Inhalt, damit eine innere Liste dort endet und Text
                    # danach nicht an ihren letzten Eintrag geraet
                    # (ttk_treeview.n 8.6: ".RE" und Text ohne ".TP")
                    lappend content $line
                }
                if {$depth > 0} {
                    incr depth -1
                } elseif {$haveItem && !$top} {
                    # .RE einer .RS ausserhalb der Liste (im Inhalt eines
                    # Eintrags): Liste zu Ende. Auf oberster Ebene bleibt sie
                    # zusammen wie bei man2markdown (nsimage.n)
                    set fertig 1
                }
            }
            .PP - .LP - .P {
                if {$depth > 0} {
                    lappend content $line
                } elseif {$haveItem && [_nextMacro $lines [expr {$i + 1}]] eq ".RS"} {
                    # ".PP .RS" nach einem Eintrag: eingerueckt wie die
                    # Definition, gehoert zum Eintrag (msgcat.n, open.n,
                    # http.n, photo.n svg; expr.n "A numeric value" ohne
                    # eigenen Text davor)
                    lappend content $line
                } else {
                    set fertig 1
                }
            }
            .SH - .SS {
                set fertig 1
            }
            .TP - .IP - .OP {
                if {$depth > 0} {
                    lappend content $line
                } elseif {$m eq ".IP" && $haveItem && $blockType eq "Dlist"
                        && [_ipTag $line] eq ""} {
                    # .IP ohne Marke nach einem .TP-Eintrag: weiterer Absatz
                    # des Eintrags (doctools: ".CE" ".IP" "assuming that ...",
                    # diagram.n)
                    lappend content .PP
                } else {
                    if {$haveItem} {
                        # Kommentar vor diesem .TP gilt ihm, nicht dem
                        # ersten .TP im Inhalt des vorigen Eintrags
                        # (man2markdown: trace.n "trace remove command")
                        set lc [dict get $P lastComment]
                        set lw [_d $P lastCmdWord ""]
                        dict set P lastComment ""
                        lappend items [_item $blockType $title $titleVs $isCmd $content $itemNum]
                        dict set P lastComment $lc
                        # innere Listen aendern den Befehl dieser Liste nicht
                        dict set P lastCmdWord $lw
                    }
                    set haveItem 1
                    set isCmd 0
                    # Escapes erst in _term (einmal; man2markdown loest sie
                    # hier und in parseInline auf, "\ec" wurde so zu "\c")
                    if {$m eq ".IP"} {
                        # .IP tag ?einzug?: ein zweites Wort, das kein
                        # Einzug ist, gehoert zum Begriff (AddOption.3:
                        # ".IP \fBTK_WIDGET_DEFAULT_PRIO\fR (20)"; wie
                        # man2markdown)
                        set ipArgs [_macroArgs $line]
                        set tag [lindex $ipArgs 0]
                        foreach w [lrange $ipArgs 1 end] {
                            if {![regexp {^[-+]?[0-9.]+[icpPmnvuM]?$} $w]} {
                                append tag " " $w
                            }
                        }
                        set title [_birp $tag]
                        # Nummer aus der Quelle (".IP [3]" nach einem Absatz
                        # zaehlt weiter, msgcat.n)
                        set itemNum ""
                        regexp {([0-9]+)} [lindex $ipArgs 0] -> itemNum
                    } elseif {$m eq ".OP"} {
                        lassign [_macroArgs $line] o1 o2 o3
                        set title "\\fB$o1\\fR"
                        if {$o2 ne "" || $o3 ne ""} {
                            append title " (\\fB$o2\\fR/\\fB$o3\\fR)"
                        }
                        set title [_birp $title]
                    } else {
                        # Begriff in der naechsten Zeile
                        incr i
                        set title [_birp [lindex $lines $i]]
                        if {[dict get $P lastComment] in {OPTION: METHOD: COMMAND: OPTION METHOD COMMAND}} {
                            set isCmd 1
                        } elseif {[_d $P lastCmdWord ""] ne ""
                                && [regexp {^\\f[BI]} $title]
                                && [_firstWord $title] eq [dict get $P lastCmdWord]} {
                            # ohne Kommentar, aber derselbe Befehl wie der
                            # Eintrag mit METHOD:/COMMAND: davor oder darueber
                            # ("after cancel script ...", "interp alias ...",
                            # photo "imageName transparency get")
                            set isCmd 1
                        }
                        if {$isCmd} {
                            dict set P lastCmdWord [_firstWord $title]
                        }
                        dict set P lastComment ""
                    }
                    set titleVs $dlistVs
                    if {$dlistVs ne ""} {
                        # in Anfuehrung: ".VS \"9.0, TIP262\"" (toplevel.n)
                        set content [list ".VS \"$dlistVs\""]
                    } else {
                        set content {}
                    }
                }
            }
            . {
                # Trenner nach dem Begriff
            }
            {.\"} {
                # innerhalb .RS/.RE gilt der Kommentar dem inneren .TP
                # (man2markdown merkt ihn sich hier und gibt ihn dem
                # falschen Eintrag: http.n -proxyhost)
                if {$depth > 0} {
                    lappend content $line
                } else {
                    dict set P lastComment [_commentWord $line]
                }
            }
            .VS {
                set dlistVs [lindex [_macroArgs $line] 0]
                lappend content $line
            }
            .VE {
                set dlistVs ""
                lappend content $line
            }
            default {
                lappend content $line
            }
        }
        if {$fertig} break
        incr i
    }
    if {$haveItem} {
        lappend items [_item $blockType $title $titleVs $isCmd $content $itemNum]
    }
    return [list [list $blockType $lattrs $items] $i]
}

# Marke einer .IP-Zeile ohne Escapes fuer Leerraum ("" bei ".IP" allein)
proc n2md::tip700::_ipTag {line} {
    set tag [lindex [_macroArgs $line] 0]
    regsub -all {\\[0&]|\\ } $tag "" tag
    return [string trim $tag]
}

# naechstes Makro ab Zeile i, .VS/.VE uebersprungen ("" fuer Text)
proc n2md::tip700::_nextMacro {lines i} {
    set n [llength $lines]
    while {$i < $n} {
        set m [_macro [lindex $lines $i]]
        if {$m ni {.VS .VE}} { return $m }
        incr i
    }
    return ""
}

# erstes Wort eines Begriffs ohne Schrift
proc n2md::tip700::_firstWord {raw} {
    return [lindex [regexp -inline {\S+} [_plain $raw]] 0]
}

proc n2md::tip700::_item {blockType title titleVs isCmd content {num ""}} {
    set b [_blocks $content]
    set leer 0
    if {![llength $b]} {
        set b [_blocks {{see below ...}}]
        set leer 1
    }
    if {$blockType eq "List"} {
        return [list ListItem [expr {$num ne "" ? [list -num $num] : {}}] $b]
    }
    # Eintrag ohne eigenen Text, gleich eine innere Definitionsliste
    # ("\fIpathName \fBtag \fIargs...\fR" .RS .TP ..., ttk_treeview.n
    # 8.6, ttk_style.n "element"/"theme"): wie ein leerer Eintrag "see
    # below ...", die innere Liste eingerueckt darunter (sonst stuende ihr
    # erster Begriff als Definition hinter ": ")
    if {[lindex $b 0 0] eq "Dlist"} {
        set b [concat [_blocks {{see below ...}}] $b]
    }
    set a [list -definition $title]
    if {$leer} { lappend a -empty 1 }
    if {$titleVs ne ""} { lappend a -vs $titleVs }
    if {$isCmd} { lappend a -cmd 1 }
    return [list DlistItem $a $b]
}

# ============================================================
# Markdown (man2markdown AST2Markdown_Element)
# ============================================================

# Span-Attribute: Klassen und fertige key="wert" unveraendert,
# "-vs wert" -> version="wert"
proc n2md::tip700::_spanAttrs {attrs} {
    set out {}
    set extra {}
    set k 0
    set n [llength $attrs]
    while {$k < $n} {
        set a [lindex $attrs $k]
        if {$a eq "-vs"} {
            incr k
            lappend extra "version=\"[lindex $attrs $k]\""
        } else {
            lappend out $a
        }
        incr k
    }
    return [join [concat $out $extra] " "]
}

# URL im Text: <url> (ohne Escapes), Satzzeichen am Ende bleiben draussen.
# In "[url]" (doctools) bleibt sie Text, das macht uriLinks.
proc n2md::tip700::_text {s} {
    if {![regexp {(?:https?|ftp)://} $s]} { return [_esc $s] }
    set out ""
    set pos 0
    while {[regexp -indices -start $pos {(?:https?|ftp)://[^\s<>"\[\]]+} $s m]} {
        lassign $m a b
        set url [string range $s $a $b]
        # ")" am Ende nur, wenn in der URL eine "(" offen ist
        while {[regexp {[.,;:!?)]$} $url]} {
            if {[string index $url end] eq ")"
                    && [regexp -all {\(} $url] >= [regexp -all {\)} $url]} break
            set url [string range $url 0 end-1]
        }
        set b [expr {$a + [string length $url] - 1}]
        append out [_esc [string range $s $pos [expr {$a - 1}]]]
        if {$a > 0 && [string index $s [expr {$a - 1}]] eq "\["} {
            append out [_esc $url]
        } else {
            append out "<$url>"
        }
        set pos [expr {$b + 1}]
    }
    append out [_esc [string range $s $pos end]]
    return $out
}

proc n2md::tip700::_mdInlines {nodes} {
    set out ""
    foreach x $nodes {
        lassign $x t a c
        switch -- $t {
            Text     { append out [_text $c] }
            Space    { append out " " }
            Strong - Emphasis {
                # nur eine URL kursiv/fett: <url> (clock.n)
                if {[llength $c] == 1 && [lindex $c 0 0] eq "Text"
                        && [regexp {^(?:https?|ftp)://\S+$} [lindex $c 0 2]]} {
                    append out [_text [lindex $c 0 2]]
                    continue
                }
                set mk [expr {$t eq "Strong" ? "**" : "*"}]
                append out $mk [_mdInlines $c] $mk
            }
            Quoted   { append out \" [_mdInlines $c] \" }
            Span     { append out "\[" [_mdInlines $c] "\]\{" [_spanAttrs $a] "\}" }
            default  { append out [_mdInlines $c] }
        }
    }
    return $out
}

# Inline-Inhalt eines Absatzknotens
proc n2md::tip700::_paraInlines {node} {
    lassign $node t a c
    if {$t eq "Inlines"} { return $c }
    return [_inline $c]
}

proc n2md::tip700::_md {parent indent node} {
    lassign $node t a c
    set pad [string repeat " " $indent]
    set out ""
    switch -- $t {
        Header {
            append out "\n" [string repeat # [dict get $a -level]] " " [_esc $c] "\n"
        }
        Paragraph - Inlines {
            set info [expr {$t eq "Paragraph" && [llength $a]}]
            set inList [expr {$parent in {List Dlist ListItem DlistItem}}]
            if {$inList} {
                append out $pad
            } else {
                append out "\n"
            }
            if {$info} {
                # auch eingerueckt mit oeffnender Zeile (man2markdown schrieb
                # in Definitionen nur das schliessende ":::", bind.n %d)
                append out "::: \{.info"
                foreach {k v} $a { append out " $k=\"$v\"" }
                append out "\}\n"
                if {[dict exists $a DISPLAY]} {
                    # je nroff-Zeile eine Zeile, harter Umbruch dazwischen
                    set ls {}
                    foreach l [split $c \n] {
                        if {[string trim $l] eq ""} continue
                        lappend ls [string trimright [_mdInlines [_paraInlines [list $t $a $l]]]]
                    }
                    append out $pad [join $ls "\\\n$pad"] "\n"
                } else {
                    append out $pad [string trimright [_mdInlines [_paraInlines $node]]] "\n"
                }
                append out $pad ":::\n"
            } else {
                append out [string trimright [_mdInlines [_paraInlines $node]]] "\n"
            }
        }
        Code {
            append out "\n" $pad "```\n"
            set ls [split [_backslash [_strip $c]] \n]
            # Leerzeilen am Ende fallen weg (doctools: Leerzeile vor .CE)
            while {[llength $ls] > 1 && [string trim [lindex $ls end]] eq ""} {
                set ls [lrange $ls 0 end-1]
            }
            foreach l $ls { append out $pad $l "\n" }
            append out $pad "```\n"
        }
        List {
            set listType [_d $a -type bullet]
            append out "\n"
            set lc 0
            foreach it $c {
                incr lc
                if {$listType eq "numbered"} {
                    # Anfang aus der Quelle (".IP [3]" nach einem Absatz,
                    # msgcat.n), danach weiter gezaehlt (TkInitStubs.3 hat
                    # zweimal "2)")
                    if {$lc == 1} { set lc [_d [lindex $it 1] -num 1] }
                    set mk "$lc. "
                } else {
                    set mk "- "
                }
                append out $pad $mk
                set first 1
                foreach b [lindex $it 2] {
                    if {$first} {
                        append out [_md ListItem 0 $b]
                        set first 0
                    } else {
                        if {[lindex $b 0] in {Paragraph Inlines}} { append out "\n" }
                        append out [_md ListItem [expr {$indent + 4}] $b]
                    }
                }
                append out "\n"
            }
        }
        Dlist {
            append out "\n"
            # kein Eintrag mit Text (doctools: Optionen ohne Beschreibung,
            # ico.n "-type fileFormat"): "see below ..." waere falsch, nichts
            # folgt; die Begriffe als Aufzaehlung. Ein einzelner leerer Eintrag
            # auf oberster Ebene bleibt "see below ..." wie bei man2markdown:
            # dort folgt der Text als Absatz (nsimage.n ".TP" ".PP")
            set alleLeer [expr {[llength $c] > 1
                || ([llength $c] == 1 && $parent in {DlistItem ListItem})}]
            foreach it $c {
                if {![_d [lindex $it 1] -empty 0]} { set alleLeer 0; break }
            }
            # leere Eintraege am Ende, danach nichts (_markTails): Aufzaehlung
            # hinter der Definitionsliste statt "see below ..."
            set rest {}
            if {!$alleLeer && [_d $a -tail 0]} {
                while {[llength $c] && [_d [lindex $c end 1] -empty 0]} {
                    set rest [linsert $rest 0 [lindex $c end]]
                    set c [lrange $c 0 end-1]
                }
                if {![llength $c]} {
                    set alleLeer 1
                    set c $rest
                    set rest {}
                }
            }
            if {$alleLeer} {
                foreach it $c {
                    append out $pad "- " [_mdInlines [_term [lindex $it 1]]] "\n"
                }
                append out "\n"
            } else {
                foreach it $c { append out [_md Dlist $indent $it] }
                if {[llength $rest]} {
                    append out "\n"
                    foreach it $rest {
                        append out $pad "- " [_mdInlines [_term [lindex $it 1]]] "\n"
                    }
                    append out "\n"
                }
            }
        }
        DlistItem {
            variable NL
            set ti [_term $a]
            # Begriff beginnt fett mit mehreren Woertern ("\fBframe center\fR",
            # pack-old.n; "\fBupdate region\fI X0\fR, ...", photo.n): ein Wert
            # oder Unterbefehl dieser Seite, kein Verweis auf einen Befehl
            set mk ""
            if {[llength $ti] >= 1 && [lindex $ti 0 0] eq "Strong"} {
                set txt ""
                foreach x [lindex $ti 0 2] {
                    if {[lindex $x 0] ne "Text"} { set txt ""; break }
                    append txt [lindex $x 2]
                }
                if {[string first " " [string trim $txt]] > 0} { set mk $NL }
            }
            append out $pad $mk [_mdInlines $ti] "\n" $pad ": "
            set first 1
            foreach b $c {
                if {$first && [lindex $b 0] ni {Paragraph Inlines}} {
                    # Liste, Code oder Definitionsliste als erster Block:
                    # eingerueckt, die erste Zeile hinter ": " (man2markdown
                    # schreibt ": " und den Block ab Spalte 0, er faellt aus
                    # der Definition)
                    set pad2 [string repeat " " [expr {$indent + 4}]]
                    set x [_md DlistItem [expr {$indent + 4}] $b]
                    regsub "^\n*$pad2" $x "" x
                    append out $x
                    set first 0
                } elseif {$first} {
                    append out [_md DlistItem 0 $b]
                    set first 0
                } else {
                    if {[lindex $b 0] in {Paragraph Inlines}} { append out "\n" }
                    append out [_md DlistItem [expr {$indent + 4}] $b]
                }
            }
            append out "\n"
        }
        Div {
            append out "\n::: \{$a\} :::\n"
            foreach b $c { append out [_md Div $indent $b] "\n" }
            append out ":::\n"
        }
        Syntax {
            append out [_mdInlines $c]
        }
    }
    return $out
}

# Definitionslisten, nach denen im selben Block nichts folgt als eine
# Ueberschrift oder ein Absatz nur in Fett (doctools "\fBMethods\fR"):
# -tail 1. Leere Eintraege am Ende einer solchen Liste haben kein "see
# below ...", unter ihnen steht nichts (httpd.n, practcl.n: Methoden ohne
# Beschreibung; pt_introduction.n "pt::pgen" allein vor der naechsten
# Ueberschrift)
proc n2md::tip700::_markTails {blocks} {
    set n [llength $blocks]
    set out {}
    for {set k 0} {$k < $n} {incr k} {
        lassign [lindex $blocks $k] t a c
        switch -- $t {
            Dlist - List {
                set items {}
                foreach it $c {
                    lassign $it it_t it_a it_c
                    lappend items [list $it_t $it_a [_markTails $it_c]]
                }
                set c $items
                if {$t eq "Dlist"} {
                    set nx [lindex $blocks [expr {$k + 1}]]
                    if {$k + 1 == $n || [lindex $nx 0] eq "Header"
                            || ([lindex $nx 0] eq "Paragraph" && ![llength [lindex $nx 1]]
                                && [regexp {^\s*\\fB[^\\]+\\f[RP]\s*$} [lindex $nx 2]])} {
                        set a [dict merge $a {-tail 1}]
                    }
                }
            }
            Div {
                set c [_markTails $c]
            }
        }
        lappend out [list $t $a $c]
    }
    return $out
}

# Begriff eines DlistItem -> Inline-Knoten
proc n2md::tip700::_term {a} {
    if {[dict exists $a -inlines]} { return [dict get $a -inlines] }
    set def [dict get $a -definition]
    set vs [_d $a -vs ""]
    if {[_d $a -cmd 0]} {
        set sp [_command [_backslash [_spaces $def]] $vs]
        # erstes Wort kein Befehl (RegConfig.3 "::\fIpkgName\fR::\fBpkgconfig\fR
        # list", man2markdown nimmt die Seite aus): Begriff als Text
        if {[lindex $sp 0 0] ne "Text"} { return $sp }
    }
    if {[dict exists $a -vs]} {
        return [list [list Span [list -vs $vs] [_inline $def]]]
    }
    return [_inline $def]
}

# ============================================================
# Links (man2markdown mdLinks)
# ============================================================

# Ziel eines Wortes -> {Gruppe Datei} oder ""
proc n2md::tip700::_target {w} {
    variable P
    variable tkCmdFileMap
    variable tclCmdFileMap
    variable tclTopicFileMap
    variable tclCApiFileMap
    variable tkCApiFileMap
    variable returnCodeFileMap
    set w [string map {\\_ _ \\* * \\\\ \\} $w]
    set ix [dict get $P index]
    # Argumente der Seite (.AP) sind keine Verweise: "argv" in Concat.3
    # ist nicht die Variable aus tclvars
    if {$w in [dict get $P cargs]} { return "" }
    if {[dict exists $ix cmds $w]} {
        return [lrange [dict get $ix cmds $w] 0 1]
    }
    if {![dict get $P core]} { return "" }
    set t ""
    if {[dict exists $tclCmdFileMap $w]} {
        set t [list Tcl [dict get $tclCmdFileMap $w]]
    } elseif {[dict exists $tclTopicFileMap $w]} {
        set t [list Tcl [dict get $tclTopicFileMap $w]]
    } elseif {[dict exists $tkCmdFileMap $w]} {
        set t [list Tk [dict get $tkCmdFileMap $w]]
    } elseif {[dict exists $tclCApiFileMap $w]} {
        set t [list TclCAPI [dict get $tclCApiFileMap $w]]
    } elseif {[dict exists $tkCApiFileMap $w]} {
        set t [list TkCAPI [dict get $tkCApiFileMap $w]]
    } elseif {[dict exists $returnCodeFileMap $w]} {
        set t [list Tcl [dict get $returnCodeFileMap $w]]
    }
    # Die festen Tabellen stammen aus Tcl/Tk 9.1. Liegt die Gruppe des
    # Ziels im Eingabeordner, muss die Seite dort auch existieren: 9.0 hat
    # kein timer.n, 8.6 kein link.n und const.n (sonst toter Link)
    if {$t ne "" && [dict exists $ix roots] && [dict exists $ix roots [lindex $t 0]]
            && [lindex $t 1] ni [dict get $ix roots [lindex $t 0]]} {
        return ""
    }
    return $t
}

# Ziel, aber nicht die eigene Seite
proc n2md::tip700::_targetOther {w} {
    variable P
    set t [_target $w]
    if {$t eq ""} { return "" }
    lassign $t g f
    if {$f eq [dict get $P file] && $g eq [dict get $P group]} { return "" }
    return $t
}

# Dateiwurzel einer Seite (nicht der eigenen) -> {Gruppe Datei} oder ""
proc n2md::tip700::_pageRoot {w} {
    variable P
    variable tclCmdFileMap
    variable tclTopicFileMap
    variable tkCmdFileMap
    set ix [dict get $P index]
    set t ""
    if {[dict exists $ix roots]} {
        dict for {g rs} [dict get $ix roots] {
            if {$w in $rs} { set t [list $g $w]; break }
        }
    }
    if {$t eq "" && [dict get $P core]} {
        foreach {g m} [list Tcl $tclCmdFileMap Tcl $tclTopicFileMap Tk $tkCmdFileMap] {
            if {$w in [dict values $m]} { set t [list $g $w]; break }
        }
    }
    if {$t eq "" || ([lindex $t 1] eq [dict get $P file] && [lindex $t 0] eq [dict get $P group])} {
        return ""
    }
    return $t
}

proc n2md::tip700::_links {md} {
    variable P
    variable NL
    variable cmdExclude
    set refs {}
    set cmdName [dict get $P cmdName]
    set excl [_d $cmdExclude [dict get $P file] {}]
    set titles {}
    foreach h [dict get $P sectionTitles] {
        dict set titles [string tolower [_esc $h]] [_esc $h]
    }
    # 1. **wort** und **wort unterbefehl**
    set re {\*\*(.+?)\*\*}
    set pos 0
    while {[regexp -indices -line -start $pos $re $md full core]} {
        set linkText [string range $md {*}$core]
        set words [split $linkText " "]
        set w0 [lindex $words 0]
        set target ""
        set internal 0
        set ok 1
        if {[llength $words] > 2 && ![string is upper [string index $w0 0]]} { set ok 0 }
        if {$ok && [string map {\\_ _} $w0] in $excl} { set ok 0 }
        # ganzer Begriff in einem Span ("[**menu**]{version=...}", wm.n):
        # kein Link im Span
        if {$ok && [string index $md [expr {[lindex $full 0] - 1}]] eq "\["
                && [string range $md [expr {[lindex $full 1] + 1}] [expr {[lindex $full 1] + 2}]] eq "\]\{"} {
            set ok 0
        }
        # Wert in einer Aufzaehlung fetter Woerter, deren Nachbarn keine
        # Befehle sind ("**readable**, **timeleft**, **variable**, and
        # **writable**", vwait.n)
        if {$ok && [llength $words] == 1 && [_inValueList $md $full $excl]} { set ok 0 }
        # Name einer Methode ("their **destroy** method", singleton.n;
        # "the **unknown** method"), eines Unterbefehls des Widgets ("the
        # **focus** widget command", canvas.n) oder einer Form des Befehls
        # ("The **before**, **after**, and **append** forms", pack-old.n),
        # auch am Ende einer Aufzaehlung: kein Befehl. ("the **ttk::entry**
        # widget commands" sind die Befehle des Widgets ttk::entry: Link)
        if {$ok && [llength $words] == 1
                && [regexp {^(?:,? (?:and |or )?\*\*[^*\n]+?\*\*)* (?:methods?|forms?|widget command)\M} [string range $md [expr {[lindex $full 1] + 1}] [expr {[lindex $full 1] + 120}]]]} {
            set ok 0
        }
        # "a method named **import text**" (tcllib toc_container.n,
        # pt_peg_container.n): Name einer Methode, kein Befehl
        if {$ok && [regexp {\m(?:method|subcommand)s? (?:named|called) $} [string range $md [expr {[lindex $full 0] - 30}] [expr {[lindex $full 0] - 1}]]]} {
            set ok 0
        }
        # Begriff ohne Link (Definitionsliste, nur fett, mehrere Woerter:
        # "frame center", pack-old.n), Marke aus _md
        if {$ok && [string index $md [expr {[lindex $full 0] - 1}]] eq $NL} {
            set ok 0
        }
        # Unterbefehl gleich nach dem kursiven Platzhalter am Zeilenanfang
        # ("*pathName* **focus** ?*tagOrId*?", Begriffe in Tk 8.6) und
        # zwei Woerter, die als Unterbefehl nach dem Platzhalter in einem
        # Begriff stehen ("later **scan dragto** commands" und "\fIpathName
        # \fBscan dragto\fR", canvas.n): kein Befehl
        if {$ok} {
            set ls [string last "\n" $md [lindex $full 0]]
            set vor [string range $md [expr {$ls + 1}] [expr {[lindex $full 0] - 1}]]
            # auch nach dem Objekt als Variable ("**$traverser** **files**",
            # tcllib traverse.n: files ist kein Link auf multiop)
            if {[regexp {^ *(?:\*[A-Za-z]+\*|\*\*\$[A-Za-z_][A-Za-z0-9_]*\*\*) $} $vor]} { set ok 0 }
        }
        if {$ok && [llength $words] > 1
                && [string map {\\_ _} [join [lrange $words 0 1]]] in [dict get $P instSubs]} {
            set ok 0
        }
        # mehrere Woerter, die eine Ueberschrift der Seite sind: Verweis auf
        # den Abschnitt, auch klein geschrieben ("see section **callback
        # invocation** below", msgcat.n)
        set secFirst [expr {[llength $words] > 1 && [dict exists $titles [string tolower $linkText]]
            && [string map {\\_ _} $w0] ne $cmdName}]
        if {$ok && !$secFirst && $w0 ne $cmdName && [string map {\\_ _} $w0] ne $cmdName} {
            set target [_targetOther $w0]
            # Befehl auch in der eigenen Uebersicht, die andere Seite nennt ihn
            # nur in ihrer Uebersicht (nicht in NAME): die eigene Seite
            # beschreibt ihn (tklib ntextIndent.n "::ntext::new_textCopy",
            # nicht ntext.n)
            if {$target ne "" && [string map {\\_ _} $w0] in [dict get $P ownSyn]
                    && [string map {\\_ _} $w0] in [_d [dict get $P index] weak {}]} {
                set target ""
            }
        }
        # "See the **ttk\_widget** manual entry" (.SO ttk_widget): Name
        # einer Seite statt eines Befehls
        if {$ok && $target eq "" && [llength $words] == 1
                && [regexp {^ manual (?:page|entry)\M} [string range $md [expr {[lindex $full 1] + 1}] [expr {[lindex $full 1] + 20}]]]} {
            set target [_pageRoot [string map {\\_ _} $w0]]
        }
        # Abschnittsverweis; nicht fuer Namen von Befehlen und C-Funktionen
        # (auch der eigenen Seite: "**Tcl\_OpenFileChannel** opens" ist
        # kein Verweis auf den Abschnitt TCL_OPENFILECHANNEL)
        if {$ok && $target eq "" && ($secFirst || (![string is lower [string index $linkText 0]]
                && [dict exists $titles [string tolower $linkText]]
                && [_target $w0] eq ""))} {
            set internal 1
        }
        # "**X** section of the **exec** command": Abschnitt einer anderen
        # Seite (open.n), kein Verweis auf die eigene
        if {$internal && [regexp {^ sections? (?:of|in) (?:the )?(?:documentation of the )?(?:\*\*|\[)} [string range $md [expr {[lindex $full 1] + 1}] [expr {[lindex $full 1] + 50}]]]} {
            set internal 0
        }
        if {$ok && ($target ne "" || $internal)} {
            if {$internal} {
                set rep "\[[dict get $titles [string tolower $linkText]]\]"
            } else {
                lassign $target g f
                set rep "\[$linkText\]"
                if {$f ne $linkText} { append rep "\[$f\]" }
                lappend refs $f $g
            }
            # "[namespace](n)" waere ein Link auf "n": Klammer escapen
            if {[string index $md [expr {[lindex $full 1] + 1}]] eq "("
                    && [string index $rep end-1] ne "\\"
                    && [regexp {^\[[^\]]*\]$} $rep]} {
                append rep "\\"
            }
            set md [string replace $md {*}$full $rep]
            set pos [expr {[lindex $full 0] + [string length $rep]}]
        } else {
            set pos [expr {[lindex $full 1] + 1}]
        }
    }
    # 2. Tcl_..., Tk_..., TCL_... im Text, nicht in Links, Spans, `code`
    set re {(\[[^]\n]*\](?:\{[^\}\n]*\}|\([^)\n]*\)|\[[^]\n]*\])?)|(`[^`\n]*`)|(\m(?:Tcl|Tk|TCL)\\_[A-Za-z0-9]+)}
    set pos 0
    while {[regexp -indices -start $pos $re $md full skip code cand]} {
        if {[lindex $cand 0] < 0} {
            set pos [expr {[lindex $full 1] + 1}]
            continue
        }
        set w [string range $md {*}$cand]
        # nicht in Ueberschriften
        set ls [string last "\n" $md [lindex $cand 0]]
        if {[string index $md [expr {$ls + 1}]] eq "#"} {
            set pos [expr {[lindex $cand 1] + 1}]
            continue
        }
        set target [_targetOther $w]
        if {$target ne ""} {
            lassign $target g f
            set rep "\[$w\]\[$f\]"
            set md [string replace $md {*}$cand $rep]
            lappend refs $f $g
            set pos [expr {[lindex $cand 0] + [string length $rep]}]
        } else {
            set pos [expr {[lindex $cand 1] + 1}]
        }
    }
    if {[llength $refs]} {
        # immer zwei Leerzeilen vor den Linkzielen (tk_mac.n: vier nach
        # verschachtelten Listen)
        set md "[string trimright $md]\n\n\n"
        set og [dict get $P group]
        foreach {f g} [lsort -dictionary -stride 2 -unique $refs] {
            if {$g ne $og} {
                append md "\[$f\]: ../$g/$f.md\n"
            } else {
                append md "\[$f\]: $f.md\n"
            }
        }
    }
    return $md
}

# Fettes Wort (Treffer full in md) mitten in einer Aufzaehlung "**a**,
# **b**, and **c**", deren Nachbarn keine Befehle sind: Wert, kein Link
proc n2md::tip700::_inValueList {md full excl} {
    lassign $full a b
    set vor [string range $md [expr {$a - 60}] [expr {$a - 1}]]
    set nach [string range $md [expr {$b + 1}] [expr {$b + 60}]]
    set nb {}
    if {[regexp {\*\*([^*\s]+)\*\*(?:, (?:and |or )?| (?:and|or) )$} $vor -> x]} { lappend nb $x }
    if {[regexp {^(?:, (?:and |or )?| (?:and|or) )\*\*([^*\s]+)\*\*} $nach -> x]} { lappend nb $x }
    # Nachbarn auf beiden Seiten, beide keine Befehle ("**sel** and
    # **my**", define.n, bleibt ein Link)
    if {[llength $nb] < 2} { return 0 }
    foreach x $nb {
        if {[string map {\\_ _} $x] ni $excl && [_target $x] ne ""} { return 0 }
    }
    return 1
}

# ============================================================
# Index eines Ordners: Befehle und C-Funktionen -> {Gruppe Datei}
# ============================================================

# .TH-Argumente, Namen aus NAME und Befehle der Uebersicht (erstes fettes
# Wort jeder Zeile in SYNOPSIS) einer Seite
proc n2md::tip700::_pageNames {text} {
    set th {}
    set names {}
    set syn {}
    set sect ""
    set txt ""
    foreach l [split [string map {"\r" ""} $text] \n] {
        if {$th eq "" && [regexp {^\.TH\s+(.*)$} $l -> rest]} {
            set th [_thArgs $rest]
            continue
        }
        if {[regexp {^\.SH\s+"?([^"]*)"?\s*$} $l -> t]} {
            set sect [string toupper [string trim $t]]
            continue
        }
        if {$sect eq "NAME" && $txt ne "-"} {
            if {[string match .* $l] || [string match '* $l]} {
                if {$txt ne ""} { set names [_nameList $txt]; set txt - }
                continue
            }
            append txt " " $l
            if {[regexp {\\-|\s-\s} $txt]} { set names [_nameList $txt]; set txt - }
        } elseif {$sect eq "SYNOPSIS"} {
            # "package require x" nennt keinen Befehl dieser Seite
            if {[regexp {^(?:\\&)?\\fB(\S+?)(?:\\f[RIPB]|\s|$)} $l -> w]
                    && ![regexp {^(?:\\&)?\\fBpackage require} $l]} {
                set w [_plain $w]
                if {[regexp {^[A-Za-z_:]} $w] && ![string match *:: $w] && $w ni $syn} {
                    lappend syn $w
                }
            }
        }
    }
    return [list $th $names $syn]
}

proc n2md::tip700::_nameList {txt} {
    regsub {(\\-|\s-\s).*$} $txt "" txt
    set names {}
    foreach x [split $txt ,] {
        set x [_plain $x]
        if {$x ne "" && ![regexp {\s} $x]} { lappend names $x }
    }
    return $names
}

proc n2md::tip700::_group {part section} {
    set g [expr {$part eq "Tk" ? "Tk" : "Tcl"}]
    if {$section eq "3"} { append g CAPI }
    return $g
}

# Ausgabegruppe einer Seite wie man2markdown: Tk (Teil "Tk" in .TH) oder
# Tcl, bei Abschnitt 3 mit CAPI
proc n2md::tip700::group {text} {
    lassign [_pageNames $text] th
    lassign $th - sect - part
    return [_group [_plain $part] [_plain $sect]]
}

proc n2md::tip700::index {dir} {
    variable indexCache
    variable notCommands
    set dir [file normalize $dir]
    if {[info exists indexCache($dir)]} { return $indexCache($dir) }
    set cmds {}
    set roots {}
    set core 0
    set files [lsort [glob -nocomplain -directory $dir -types f *.n *.1 *.3]]
    foreach f $files {
        if {[catch {
            set fh [open $f]
            fconfigure $fh -encoding utf-8
            set t [read $fh]
            close $fh
        }]} continue
        lassign [_pageNames $t] th names syn
        lassign $th thName thSect - thPart
        set thPart [_plain $thPart]
        set thSect [_plain $thSect]
        if {$thPart in {Tcl Tk}} { set core 1 }
        set g [_group $thPart $thSect]
        set root [file rootname [file tail $f]]
        dict lappend roots $g $root
        # C-Schnittstelle: alle Namen aus NAME. Sonst die Befehle, die in der
        # Uebersicht stehen (nicht "safe" in safe.n, dessen Befehle
        # ::safe::interpCreate usw. heissen); steht der Name auch in NAME,
        # gilt diese Seite vor anderen, die ihn nur in der Uebersicht nennen
        # (oo::define in configurable.n). Seiten ohne Uebersicht (tclvars,
        # re_syntax, filename; Tk: options, tkvars) mit allen Namen aus NAME.
        set art ""
        if {$thSect eq "3" || ![llength $syn]} {
            set stark $names
            set schwach {}
            if {$thSect ne "3"} { set art thema }
        } else {
            set stark {}
            set schwach {}
            foreach x $syn {
                if {$x in $names} { lappend stark $x } else { lappend schwach $x }
            }
        }
        foreach x $stark {
            if {$x in $notCommands} continue
            if {![dict exists $cmds $x] || [lindex [dict get $cmds $x] 2] eq "schwach"} {
                dict set cmds $x [concat [list $g $root] $art]
            }
        }
        foreach x $schwach {
            if {$x in $notCommands} continue
            # Platzhalter statt Befehl: steht auf der Seite auch kursiv
            # (refchan.n/transchan.n 8.6: "\fBcmdPrefix \fIoption\fR" in der
            # Uebersicht, im Text "\fIcmdPrefix\fR"); nicht fuer Namen mit
            # "::" (doctools: "category \fIwidget::calendar\fR")
            if {[string first :: $x] < 0 && [string first "\\fI$x" $t] >= 0
                    && [regexp "\\\\fI[_reQuote $x](?!\[A-Za-z0-9_:\])" $t]} continue
            # mehrere Seiten nennen ihn nur in der Uebersicht: die Seite, deren
            # Dateiname der Befehl ist ("widget::calendar" ->
            # widget_calendar.n, nicht widget.n mit allen Befehlen; tklib)
            if {![dict exists $cmds $x]
                    || ([lindex [dict get $cmds $x] 2] eq "schwach"
                        && $root eq [string map {:: _} [string trimleft $x :]])} {
                dict set cmds $x [list $g $root schwach]
            }
        }
    }
    set weak {}
    dict for {x v} $cmds {
        if {[lindex $v 2] eq "schwach"} {
            dict set cmds $x [lrange $v 0 1]
            lappend weak $x
        }
    }
    set indexCache($dir) [dict create cmds $cmds core $core roots $roots weak $weak]
    return $indexCache($dir)
}

# ============================================================
# Hauptprozedur
# ============================================================

# convert nroffText ?-file datei? ?-dir ordner? ?-index ix?
#   -file  Pfad der Seite (Dateiwurzel fuer Ausschluesse und Links; ihr
#          Ordner liefert den Index, wenn -dir fehlt)
#   -dir   Ordner fuer den Index (Befehle -> Seiten)
#   -index fertiger Index (index)
proc n2md::tip700::convert {text args} {
    variable P
    variable NL
    set o [dict merge {-file "" -dir "" -index ""} $args]
    set file [dict get $o -file]
    set lines [_prep $text]
    set th [_th $lines]
    lassign $th name sect ver part desc
    set name [_plain $name]
    set sect [_plain $sect]
    set part [_plain $part]
    set root [expr {$file ne "" ? [file rootname [file tail $file]] : $name}]
    # Index: Ordner der Seite
    set ix [dict get $o -index]
    if {$ix eq ""} {
        set dir [dict get $o -dir]
        if {$dir eq "" && $file ne "" && [file exists $file]} {
            set dir [file dirname $file]
        }
        if {$dir ne "" && [file isdirectory $dir]} {
            set ix [index $dir]
        } else {
            set ix [dict create cmds {} core 0]
        }
    }
    set core [expr {[dict get $ix core] || $part in {Tcl Tk}}]
    # Argumentnamen (.AP typ name): "*argv", "argv[]" -> argv
    set cargs {}
    foreach l $lines {
        if {[regexp {^\.AP\s} $l]} {
            set a [lindex [_macroArgs $l] 1]
            set a [string trimright [string trimleft [_plain $a] "*&"] "\[\]"]
            if {$a ne ""} { lappend cargs $a }
        }
    }
    # Unterbefehle aus zwei Woertern nach einem Platzhalter ("\fIpathName
    # \fBscan mark", "\fIpathName \fBselection anchor") fuer _links
    set instSubs {}
    foreach l $lines {
        if {[regexp {^\\fI[A-Za-z]+ ?\\fB ?([A-Za-z]+) ([A-Za-z]+)} $l -> w1 w2]
                && "$w1 $w2" ni $instSubs} {
            lappend instSubs "$w1 $w2"
        }
    }
    set ownSyn [lindex [_pageNames $text] 2]
    set P [dict create file $root cmdName $name section $sect part $part cargs $cargs instSubs $instSubs ownSyn $ownSyn \
        group [_group $part $sect] index $ix core $core \
        meta {} sectionTitles {} lastComment "" lastCmdWord "" lastStdOpt "" \
        wordForms [_wordForms $lines]]
    # Kopf
    set head "---\n"
    append head "CommandName: [_yval $name]\n"
    append head "title: [_yval $name]\n"
    append head "ManualSection: [_yval $sect]\n"
    set ver [_plain $ver]
    if {$ver eq ""} { set ver unknown }
    append head "Version: [_yval $ver]\n"
    append head "TclPart: [_yval $part]\n"
    append head "TclDescription: [_yval [_plain $desc]]\n"
    set blocks [_markTails [_blocks $lines 1]]
    foreach {k v} [dict get $P meta] {
        append head "$k:\n"
        foreach w $v { append head " - [_yval $w]\n" }
    }
    append head "Copyright:\n"
    foreach l $lines {
        if {[regexp {^[.']\\"\s*(Copyright\M.*)$} $l -> c]} {
            append head " - [_yval [regsub -all {\s+} [_plain $c] " "]]\n"
        }
    }
    append head "---\n"
    set body ""
    foreach b $blocks { append body [_md Document 0 $b] }
    set md [string map [list $NL ""] [_links "$head$body"]]
    # keine Leerzeichen am Zeilenende (open.n: Begriff "Windows ")
    regsub -all -line {[ ]+$} $md "" md
    regsub {\s+$} $md "\n" md
    set md [string map [list "\n\n:::\n" "\n:::\n"] $md]
    return [uriLinks $md]
}

# Wie 0.1: render nroffText ?ir? -- ir (DocIR) wird nicht mehr gebraucht
proc n2md::tip700::render {text {ir {}} args} {
    return [convert $text {*}$args]
}

# doctools schreibt Verweise als "\fIRFC 4648\fR [https://...]" (tcllib,
# tklib); im Markdown stand dann "*RFC 4648* \[https://...\]". Daraus ein
# Link; eine URL ohne Text davor wird <https://...>.
proc n2md::tip700::uriLinks {md} {
    set re {(?:\*([^*\n]+)\* )?\\\[((?:https?|ftp|mailto):[^\s\]]+?)\\\]}
    set out ""
    set pos 0
    while {[regexp -indices -start $pos $re $md m t u]} {
        lassign $m a b
        append out [string range $md $pos [expr {$a - 1}]]
        set url [string map {\\_ _ \\* * \\$ $ \\< <} [string range $md {*}$u]]
        if {[lindex $t 0] >= 0} {
            append out "\[[string range $md {*}$t]\]($url)"
        } else {
            append out "<$url>"
        }
        set pos [expr {$b + 1}]
    }
    append out [string range $md $pos end]
    return $out
}

package provide n2md::tip700 0.2
