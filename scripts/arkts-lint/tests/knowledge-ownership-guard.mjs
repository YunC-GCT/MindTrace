// Ownership guard, not a module-layout snapshot: scan every production source,
// resolve aliases/barrels, and inspect references to the owned declarations.
import { createRequire } from 'node:module';
import { posix } from 'node:path';
const require = createRequire(import.meta.url);
const ts = require('typescript');

const nodePath = 'agents/src/main/ets/graph/nodes/TruthCheckNode.ets';
const ownedGraphNames = new Set(['AgentState', 'CaptureGraph']);
const truthServiceName = 'TruthCheckService';

export function ownershipViolations(sources) {
  const files = new Map([...sources].map(([path, source]) => [path,
    ts.createSourceFile(path, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS)]));
  function resolveModule(request, from) {
    const base = request.startsWith('.') ? posix.join(posix.dirname(from), request) : request;
    return [base, `${base}.ets`, `${base}.ts`, `${base}/src/main/ets/Index.ets`]
      .find(path => files.has(path));
  }
  const host = {
    getSourceFile: path => files.get(path),
    getDefaultLibFileName: () => '', writeFile() {},
    getCurrentDirectory: () => '', getDirectories: () => [],
    fileExists: path => files.has(path), readFile: path => sources.get(path),
    getCanonicalFileName: path => path, useCaseSensitiveFileNames: () => true,
    getNewLine: () => '\n',
    resolveModuleNames: (names, from) => names.map(name => {
      const path = resolveModule(name, from);
      return path ? { resolvedFileName: path, extension: ts.Extension.Ts } : undefined;
    }),
  };
  // ArkUI-only syntax may have TS parse diagnostics; this is symbol analysis,
  // not ArkTS typechecking. Ownership seams use ordinary TS-compatible ETS.
  const program = ts.createProgram([...files.keys()], { noLib: true, noResolve: false,
    allowNonTsExtensions: true, target: ts.ScriptTarget.ES2020 }, host);
  const checker = program.getTypeChecker();
  const graphSymbols = new Set();
  const truthServiceSymbols = new Set();
  function noteOwnerDeclaration(node) {
    if (!node.name || !ts.isIdentifier(node.name)) return;
    const symbol = checker.getSymbolAtLocation(node.name);
    if (!symbol) return;
    if (ownedGraphNames.has(node.name.text)) graphSymbols.add(symbol);
    if (node.name.text === truthServiceName) truthServiceSymbols.add(symbol);
  }
  for (const file of files.values()) {
    ts.forEachChild(file, node => {
      if (ts.isClassDeclaration(node) || ts.isInterfaceDeclaration(node) || ts.isTypeAliasDeclaration(node)) {
        noteOwnerDeclaration(node);
      }
    });
  }
  function ownsDeclaration(symbolSet, declaration) {
    if (!declaration || !declaration.parent) return false;
    const parent = declaration.parent;
    if ((ts.isClassDeclaration(parent) || ts.isInterfaceDeclaration(parent) || ts.isTypeAliasDeclaration(parent)) &&
        parent.name) {
      const parentSymbol = checker.getSymbolAtLocation(parent.name);
      return parentSymbol !== undefined && symbolSet.has(parentSymbol);
    }
    const symbol = declaration.name ? checker.getSymbolAtLocation(declaration.name) : undefined;
    return symbol !== undefined && symbolSet.has(symbol);
  }
  function fileDeclaresOwnedGraph(path) {
    const file = files.get(path);
    if (!file) return false;
    let found = false;
    ts.forEachChild(file, node => {
      if ((ts.isClassDeclaration(node) || ts.isInterfaceDeclaration(node) || ts.isTypeAliasDeclaration(node)) &&
          node.name && graphSymbols.has(checker.getSymbolAtLocation(node.name))) {
        found = true;
      }
    });
    return found;
  }
  const found = new Set();
  for (const [path, file] of files) {
    function visit(node) {
      if (ts.isIdentifier(node) ||
          (ts.isStringLiteral(node) && ts.isElementAccessExpression(node.parent))) {
        let symbol = checker.getSymbolAtLocation(node);
        if (symbol && (symbol.flags & ts.SymbolFlags.Alias)) symbol = checker.getAliasedSymbol(symbol);
        for (const declaration of symbol?.declarations ?? []) {
          if (path.startsWith('entry/src/main/') && ownsDeclaration(graphSymbols, declaration)) {
            found.add(`${path}: entry depends on CaptureGraph/AgentState`);
          }
          // Includes taking a method reference (bind/alias), not only direct calls.
          if (ts.isMethodDeclaration(declaration) && ownsDeclaration(truthServiceSymbols, declaration) &&
              path !== nodePath && path !== declaration.getSourceFile().fileName) {
            found.add(`${path}: TruthCheck invocation belongs to TruthCheckNode`);
          }
        }
      }
      // Importing a graph namespace without using it is still a dependency.
      if (path.startsWith('entry/src/main/') &&
          (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) && node.moduleSpecifier) {
        const target = resolveModule(node.moduleSpecifier.text, path);
        if (target && fileDeclaresOwnedGraph(target)) {
          found.add(`${path}: entry depends on CaptureGraph/AgentState`);
        }
      }
      ts.forEachChild(node, visit);
    }
    visit(file);
  }
  return [...found].sort();
}
