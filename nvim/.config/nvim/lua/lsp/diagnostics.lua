-- Native pull diagnostics own refresh and hidden-buffer synchronization.
return {
	["textDocument/diagnostic"] = vim.lsp.diagnostic.on_diagnostic,
	["textDocument/publishDiagnostics"] = function(err, result, ctx)
		-- Push servers can finish an older analysis after the buffer has changed.
		-- Unversioned reports remain native; their freshness cannot be inferred.
		if result.version then
			local buf = vim.fn.bufnr(vim.uri_to_fname(result.uri))
			local version = vim.lsp.util.buf_versions[buf]
			if version and result.version < version then
				return
			end
		end
		vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx)
	end,
}
