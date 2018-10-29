%define luaver 5.1
%define luapkgdir %{_datadir}/lua/%{luaver}

Name:           lua-argparse
Version:        0.6.0
Release:        1pdns%{?dist}
Summary:        Feature-rich command line parser for Lua

Group:          Development/Libraries
License:        MIT
URL:            https://github.com/mpeterv/argparse
Source0:        https://github.com/mpeterv/argparse/archive/%{version}.tar.gz

BuildArch:      noarch

BuildRequires:  lua >= %{luaver}, lua-devel >= %{luaver}
Requires:       lua >= %{luaver}

%description
Argparse is a feature-rich command line parser for Lua inspired by argparse for Python.

%prep
%setup -q -n argparse-%{version}

%install
%{__rm} -rf %{buildroot}
%{__mkdir_p} %{buildroot}%{luapkgdir}
%{__mkdir_p} %{buildroot}%{luapkgdir}
%{__install} -m 0664 src/argparse.lua %{buildroot}%{luapkgdir}

%clean
%{__rm} -rf %{buildroot}

%files
%defattr(-,root,root,-)
%doc README.md LICENSE
%{luapkgdir}/*
