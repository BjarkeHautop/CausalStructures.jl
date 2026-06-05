# Circle layout: n nodes placed clockwise from the top of a unit circle.

function _circle_layout(n::Int)
    n == 0 && return Point2f[]
    n == 1 && return [Point2f(0.0f0, 0.0f0)]
    step = 2.0f0 * Float32(π) / n
    return [
        Point2f(
            cos(Float32(π) / 2.0f0 - (i - 1) * step),
            sin(Float32(π) / 2.0f0 - (i - 1) * step),
        ) for i = 1:n
    ]
end
