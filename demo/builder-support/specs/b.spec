%if %{?rhel} < 6
exit 1
%endif

%define src_name demo-b
%define src_version %{getenv:BUILDER_VERSION}

Name:           %{src_name}
Version:        %{getenv:BUILDER_RPM_VERSION}
Release:        %{getenv:BUILDER_RPM_RELEASE}%{dist}
Summary:        PowerDNS builder demo package A
BuildArch:      noarch

Group:          System
License:        MIT
URL:            https://github.com/PowerDNS/pdns-builder
Source0:        %{src_name}-%{src_version}.tar.gz

%description
A demo package for the PowerDNS builder.

%prep
%autosetup -n %{src_name}-%{src_version}

%install
ls
%{__mkdir} -p %{buildroot}%{_bindir}
%{__cp} demo-b.sh %{buildroot}%{_bindir}/demo-b

%files
%{_bindir}/*
