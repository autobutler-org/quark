package provisionutil

type provisionRequest struct {
	DeviceID       string `json:"device_id"`
	Household      string `json:"household,omitempty"`
	HouseholdToken string `json:"household_token,omitempty"`
}

type provisionResponse struct {
	AuthKey        string `json:"auth_key"`
	Household      string `json:"household"`
	HouseholdToken string `json:"household_token"`
}
