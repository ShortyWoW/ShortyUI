local _, ns = ...

ns.resource_modules = ns.resource_modules or {}

function ns.RegisterResourceModule(class_file, module)
  if not (class_file and module) then
    return
  end

  ns.resource_modules[class_file] = module
end

function ns.GetResourceModule(class_file)
  if not class_file then
    return nil
  end

  return ns.resource_modules and ns.resource_modules[class_file] or nil
end
