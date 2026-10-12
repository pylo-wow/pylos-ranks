local addonName, ns = ...

-- Announces the addon to Pylos Core (ns.L, options page from ns.options, ns.off).
if not PylosCore.Module(addonName, ns, { requires = { core = "1.0" } }) then return end
