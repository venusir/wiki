# Update China IP

```
:log info "start download address-list.rsc ..."
/tool fetch http-method=get url=https://raw.githubusercontent.com/zealic/autorosvpn/master/address-list.rsc
:log info "address-list.rsc downloaded."
/import file=address-list.rsc
/file remove [find name="address-list.rsc"]
:log info "NoVPN address list updated!"
```