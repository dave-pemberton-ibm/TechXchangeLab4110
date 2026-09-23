URL="https://dev3048403.a-vir-r1.int.ipaas.automation.ibm.com/integration/restv2/development/fl0cd7334a11e5496c91e1f959a3f532df/cruising"
APIKEY="azI6ZDc1YmU4ODgtMThmYS00YjNiLTlhZWMtMDZkMTA1YTQ0MDkyOk4rUVI4R1diVGxmeHcxZk5rOEtiMmRqQUtiNHRTbnlVTTFnaDRlNysybGc9"

curl -X GET \
  "${URL}/getPassenger360?passenger_id=P12345" \
  -H "Accept: application/json" \
  -H "X-INSTANCE-API-KEY: ${APIKEY}"

