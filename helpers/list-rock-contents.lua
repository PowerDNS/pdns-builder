#!/usr/bin/env lua5.1
-- Build helper that extracts a list of required files from a rockspec.
-- The builder uses this list to create the source tarball.

local rockspecpath = arg[1]
local rockspec = assert(loadfile(rockspecpath))
-- This will set globals
rockspec()

if build then
    if build.modules then
        for name,path in pairs(build.modules) do
            print(path)
        end
    end
    if build.install then
        for type,spec in pairs(build.install) do
            for name,path in pairs(spec) do
                print(path)
            end
        end
    end
end
