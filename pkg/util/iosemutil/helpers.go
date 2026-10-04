package iosemutil

// classSlots is how many holders class c admits on a host with that many cores.
// The reasoning for each size is on the class's constant.
func classSlots(c Class, cores int) int {
	switch c {
	case Decode:
		return max(2, cores/2)
	case Video:
		return max(1, cores/2)
	case Raw:
		return max(1, cores/4)
	}
	return 2
}
