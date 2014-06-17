Summary: SFIT Cloud Initialization Tool for OpenStack
Name: sfit-cloud-init
Version: %{version}
Release: %{release}
License: SFIT
Group: Applications/System
Source: %{name}-%{version}.tar.gz
URL: http://www.sfit.com.cn
Vendor: SFIT
Prefix: %{instdir}
BuildRoot: %{_tmppath}/%{name}-%{version}-root
#BuildPrereq:
#Requires:
Prereq: /bin/rm, /bin/mv, /bin/mkdir
Prereq: util-linux

%description
%SFIT Cloud Initialization Tool for OpenStack

%prep
%setup -c

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT%{instdir}/cookbooks
cp -r * $RPM_BUILD_ROOT%{instdir}/cookbooks/
rm -f $RPM_BUILD_ROOT%{instdir}/cookbooks/cookbooks.spec

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(755,root,root)
%{instdir}/cookbooks/*/


%changelog
* Fri Jun 13 2014 Sun Haixuan <sunhaixuan@gmail.com>
- Initial version
